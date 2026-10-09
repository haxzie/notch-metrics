import { and, asc, eq, isNull, lte, ne, or } from "drizzle-orm";
import {
  credentialExpiry,
  getAdapter,
  isRefreshDue,
  OAuthReauthRequiredError,
} from "@notch/integrations";
import { ProviderId } from "@notch/schemas";
import { integration as integrationTable } from "@notch/db";
import type { Env } from "../env.ts";
import { openCredentials, sealCredentials, sealedFromRow } from "./crypto.ts";
import type { Database } from "./db.ts";
import { oauthClient } from "./oauth-client.ts";
import { logError } from "./redact.ts";
import { notifyBroken } from "./slack.ts";

type Row = typeof integrationTable.$inferSelect;

/**
 * Consecutive non-fatal refresh failures tolerated before a row is marked as
 * needing reconnection — and only once the token is actually past its
 * expiry. With an hour of lead and a five-minute floor, three strikes is
 * fifteen minutes of a provider being down, and the token is still good for
 * another forty-five. Giving up earlier makes somebody redo a sign-in to
 * recover from an outage that was never theirs.
 */
export const REFRESH_STRIKE_LIMIT = 3;

/** Rows per provider per tick. A backlog rolls to the next tick; a timeout refreshes nothing. */
const SWEEP_BATCH = 50;

/**
 * Opens a row's credentials, refreshing them first if the connector's policy
 * says they are due.
 *
 * The single implementation behind both the cron sweep and every metric
 * fetch, so a request that lands inside the lead window gets a fresh token
 * without waiting for the next tick, and the two paths cannot drift. Never
 * throws on a refresh failure: the credentials we already hold are returned,
 * and whatever they can still do, they do.
 */
export async function openFreshCredentials(
  env: Env,
  db: Database,
  row: Row,
): Promise<{ credentials: Record<string, string>; refreshed: boolean }> {
  const adapter = getAdapter(row.provider);
  const scope = { userId: row.userId, integrationId: row.id, provider: row.provider };
  const credentials = await openCredentials(env, scope, sealedFromRow(row));

  const policy = adapter.oauth?.refresh;
  if (!adapter.oauth || !policy) return { credentials, refreshed: false };

  const expiresAt = credentialExpiry(credentials);
  const due = isRefreshDue(policy, {
    expiresAt,
    lastAttemptAt: row.lastRefreshAttemptAt?.getTime() ?? null,
  });
  if (!due) return { credentials, refreshed: false };

  const client = oauthClient(env, row.provider);
  if (!client) {
    // A connection exists, so the secrets were there once. Say so rather
    // than silently letting the token lapse.
    logError(
      `oauth.refresh.${row.id}`,
      new Error(`no OAuth client configured for ${row.provider}`),
    );
    return { credentials, refreshed: false };
  }

  const now = new Date();
  try {
    const next = await adapter.oauth.refreshCredentials({
      credentials,
      clientId: client.clientId,
      clientSecret: client.clientSecret,
    });

    if (!next) {
      // Nothing to rotate — a non-expiring token. Recording the attempt is
      // what stops the sweep reconsidering the row before the floor.
      await db
        .update(integrationTable)
        .set({ lastRefreshAttemptAt: now, refreshFailures: 0 })
        .where(eq(integrationTable.id, row.id));
      return { credentials, refreshed: false };
    }

    const parsed = adapter.credentialSchema.parse(next) as Record<string, string>;
    const sealed = await sealCredentials(env, scope, parsed);
    const nextExpiry = credentialExpiry(parsed);
    await db
      .update(integrationTable)
      .set({
        credentialCiphertext: sealed.ciphertext,
        credentialIv: sealed.iv,
        credentialWrappedDek: sealed.wrappedDek,
        keyVersion: sealed.keyVersion,
        credentialHint: sealed.hint,
        credentialFingerprint: sealed.fingerprint,
        tokenExpiresAt: nextExpiry === null ? null : new Date(nextExpiry),
        lastRefreshAttemptAt: now,
        refreshFailures: 0,
      })
      .where(eq(integrationTable.id, row.id));
    return { credentials: parsed, refreshed: true };
  } catch (error) {
    if (error instanceof OAuthReauthRequiredError) {
      // The grant is gone. Retrying is how a client id gets throttled, and
      // the only fix is the person who granted it.
      await db
        .update(integrationTable)
        .set({
          status: "auth_failed",
          lastErrorCode: "auth_failed",
          lastErrorAt: now,
          lastRefreshAttemptAt: now,
        })
        .where(eq(integrationTable.id, row.id));
      await notifyBroken(env, db, row.status, row);
      return { credentials, refreshed: false };
    }

    logError(`oauth.refresh.${row.id}`, error);
    const failures = row.refreshFailures + 1;
    const expired = expiresAt !== null && expiresAt <= now.getTime();
    const giveUp = failures >= REFRESH_STRIKE_LIMIT && expired;
    await db
      .update(integrationTable)
      .set({
        refreshFailures: failures,
        lastRefreshAttemptAt: now,
        ...(giveUp
          ? { status: "auth_failed", lastErrorCode: "auth_failed", lastErrorAt: now }
          : {}),
      })
      .where(eq(integrationTable.id, row.id));
    if (giveUp) await notifyBroken(env, db, row.status, row);
    return { credentials, refreshed: false };
  }
}

/**
 * Refreshes every OAuth integration whose token is inside its connector's
 * lead window. Runs on the cron, ahead of the metric poll, so the poll uses
 * the new tokens.
 *
 * The due-check is in SQL against the mirrored expiry, so a tick where
 * nothing is due costs one indexed query per refreshable connector and
 * touches no provider. One query per connector rather than one for all,
 * because each has its own lead time and floor.
 */
export async function sweepTokenRefresh(
  db: Database,
  env: Env,
): Promise<{ candidates: number; refreshed: number; failed: number }> {
  const now = Date.now();
  let candidates = 0;
  let refreshed = 0;
  let failed = 0;

  for (const providerId of ProviderId.options) {
    const policy = getAdapter(providerId).oauth?.refresh;
    if (!policy) continue;

    const rows = await db
      .select()
      .from(integrationTable)
      .where(
        and(
          eq(integrationTable.provider, providerId),
          // A dead grant is never retried here either.
          ne(integrationTable.status, "auth_failed"),
          or(
            isNull(integrationTable.tokenExpiresAt),
            lte(integrationTable.tokenExpiresAt, new Date(now + policy.leadTimeMs)),
          ),
          or(
            isNull(integrationTable.lastRefreshAttemptAt),
            lte(integrationTable.lastRefreshAttemptAt, new Date(now - policy.minIntervalMs)),
          ),
        ),
      )
      .orderBy(asc(integrationTable.tokenExpiresAt))
      .limit(SWEEP_BATCH);

    candidates += rows.length;
    // Sequential, not Promise.all: the floor is per row but the provider's
    // token endpoint is rate-limited per client id, and a Worker has one.
    for (const row of rows) {
      try {
        if ((await openFreshCredentials(env, db, row)).refreshed) refreshed++;
      } catch (error) {
        // openFreshCredentials swallows refresh failures, so this is
        // structural: a blob that will not decrypt, a schema that drifted.
        failed++;
        logError(`cron.tokenRefresh.${row.id}`, error);
      }
    }
  }

  return { candidates, refreshed, failed };
}
