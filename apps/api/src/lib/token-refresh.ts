import { and, asc, eq, isNull, lte, or } from "drizzle-orm";
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
import { trackBroken } from "./track.ts";
import { emitConnectionBroken } from "./notifications.ts";
import { recordEvent } from "./events.ts";

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
 * Claims the right to call the token endpoint for one row, or returns false
 * because somebody else holds it.
 *
 * `lastRefreshAttemptAt` is written *before* the call rather than after, by a
 * conditional update only one caller can win. The floor `isRefreshDue`
 * applies is advisory on its own: every caller reads the row before any of
 * them writes it, so two that arrive together both see a token that is due
 * and both post.
 *
 * That gap was not theoretical. GitHub's refresh token is single-use, so the
 * caller that lost was answered `bad_refresh_token` — read below, correctly
 * in isolation, as a dead grant — and marked a healthy connection as needing
 * reauthorisation. Two overlapping `/v1/metrics/batch` requests from one
 * woken Mac were enough, and it cost roughly one GitHub connection in six
 * refreshes. Google's refresh token survives being used, which is why only
 * GitHub ever showed it.
 *
 * The claim lasts `minIntervalMs` — the floor is also the lease, so an
 * isolate that dies mid-refresh costs one cycle of waiting rather than a
 * stuck row.
 */
async function claimRefresh(
  db: Database,
  row: Row,
  policy: { minIntervalMs: number },
  now: Date,
): Promise<boolean> {
  const claimed = await db
    .update(integrationTable)
    .set({ lastRefreshAttemptAt: now })
    .where(
      and(
        eq(integrationTable.id, row.id),
        or(
          isNull(integrationTable.lastRefreshAttemptAt),
          lte(
            integrationTable.lastRefreshAttemptAt,
            new Date(now.getTime() - policy.minIntervalMs),
          ),
        ),
      ),
    )
    .returning({ id: integrationTable.id });
  return claimed.length > 0;
}

/**
 * The row as it is now, if its credentials have been replaced since `row` was
 * read — otherwise null.
 *
 * Compared on the fingerprint, which is a digest of the plaintext blob and so
 * changes with every new access token. A ciphertext comparison would not do:
 * the same credentials re-sealed produce different bytes.
 */
async function rotatedSince(db: Database, row: Row): Promise<Row | null> {
  const current = (
    await db.select().from(integrationTable).where(eq(integrationTable.id, row.id)).limit(1)
  )[0];
  if (!current) return null;
  return current.credentialFingerprint === row.credentialFingerprint ? null : current;
}

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
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "refresh",
      outcome: "skipped",
      reason: "no_oauth_client",
      detail: `no OAuth client configured for ${row.provider}`,
    });
    return { credentials, refreshed: false };
  }

  const now = new Date();
  const startedAt = Date.now();

  if (!(await claimRefresh(db, row, policy, now))) {
    // Somebody else is mid-refresh on this row. Returning the blob we opened
    // is not good enough for a connector that rotates: the winner's new
    // token revokes ours, and our widgets would 401 on a connection that is
    // perfectly healthy. Re-read instead, and use the winner's work if it
    // has landed — if it has not, ours is still the current credential.
    const rotated = await rotatedSince(db, row);
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "refresh",
      outcome: "skipped",
      reason: rotated ? "claimed_elsewhere_rotated" : "claimed_elsewhere",
      durationMs: Date.now() - startedAt,
    });
    if (!rotated) return { credentials, refreshed: false };
    return {
      credentials: await openCredentials(env, scope, sealedFromRow(rotated)),
      refreshed: false,
    };
  }

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
      await recordEvent(db, {
        userId: row.userId,
        integrationId: row.id,
        kind: "refresh",
        outcome: "skipped",
        reason: "nothing_to_rotate",
        durationMs: Date.now() - startedAt,
      });
      return { credentials, refreshed: false };
    }

    const parsed = adapter.credentialSchema.parse(next) as Record<string, string>;
    const sealed = await sealCredentials(env, scope, parsed);
    const nextExpiry = credentialExpiry(parsed);

    // A refresh that *succeeded* proves the grant is alive, so a row sitting
    // in `auth_failed` because the data path rejected some request is now
    // demonstrably recoverable and is let back in. Without this the only way
    // out of `auth_failed` is a human, which is how a connection broken by a
    // renamed repository stayed broken. A genuinely dead grant cannot reach
    // this line — it throws `OAuthReauthRequiredError` below.
    const recovering = row.status === "auth_failed";

    // The reauth demand goes with it, and for the same reason. This used to
    // be the one mark a success could not lift, on the reasoning that only
    // the person who granted it should — but the sweep is not the only
    // caller. The fetch path refreshes rows the sweep excludes, so a demand
    // raised in error outlived its cause: the production GitHub row carried
    // one for three days reading `status: ok`, refreshed by whichever
    // request happened to notice and never pre-warmed by the cron at all.
    // Kept separate from `recovering` so a `disabled` row is not quietly
    // switched back on by a token refresh.
    const demandWasStale = row.reauthRequiredAt !== null;

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
        ...(recovering
          ? { status: "ok", lastErrorCode: null, authFailures: 0, failureCount: 0 }
          : {}),
        ...(demandWasStale ? { reauthRequiredAt: null } : {}),
      })
      .where(eq(integrationTable.id, row.id));

    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "refresh",
      outcome: "ok",
      durationMs: Date.now() - startedAt,
      detail:
        nextExpiry === null
          ? "no expiry reported"
          : `expires ${new Date(nextExpiry).toISOString()}`,
    });
    if (recovering || demandWasStale) {
      await recordEvent(db, {
        userId: row.userId,
        integrationId: row.id,
        kind: "status",
        outcome: "ok",
        code: "ok",
        detail: demandWasStale
          ? "recovered: refresh succeeded while marked as needing reauthorisation"
          : "recovered: refresh succeeded while marked auth_failed",
      });
    }
    return { credentials: parsed, refreshed: true };
  } catch (error) {
    if (error instanceof OAuthReauthRequiredError) {
      // Unless it is not gone at all. A single-use refresh token spent by
      // another caller while ours was in the air answers exactly like a
      // revoked one, and the proof that it was the former is sitting in the
      // row: new credentials, minted from the token we were just told is
      // dead. `claimRefresh` above is what stops the race; this is what
      // keeps losing one from being fatal, for a lease lost to a D1 hiccup
      // or a second isolate that read the row before the claim landed.
      const rotated = await rotatedSince(db, row);
      if (rotated) {
        await recordEvent(db, {
          userId: row.userId,
          integrationId: row.id,
          kind: "refresh",
          outcome: "skipped",
          reason: "lost_refresh_race",
          durationMs: Date.now() - startedAt,
          detail: "refresh token already spent by a concurrent refresh; grant is alive",
        });
        return {
          credentials: await openCredentials(env, scope, sealedFromRow(rotated)),
          refreshed: false,
        };
      }

      // The grant is gone. Retrying is how a client id gets throttled, and
      // the only fix is the person who granted it. `reauthRequiredAt` is
      // what the sweep excludes on — this is the one case where there is
      // genuinely nothing left to refresh.
      await db
        .update(integrationTable)
        .set({
          status: "auth_failed",
          lastErrorCode: "auth_failed",
          lastErrorAt: now,
          lastRefreshAttemptAt: now,
          reauthRequiredAt: now,
        })
        .where(eq(integrationTable.id, row.id));
      await recordEvent(db, {
        userId: row.userId,
        integrationId: row.id,
        kind: "refresh",
        outcome: "error",
        code: "auth_failed",
        reason: "reauth_required",
        durationMs: Date.now() - startedAt,
        detail: error.message,
      });
      // The user's notification first, then ours. The Slack ping is gated on a
      // webhook secret being configured; the user's is not.
      await emitConnectionBroken(db, row.status, row);
      await trackBroken(env, db, row.status, row);
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
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "refresh",
      outcome: "error",
      code: giveUp ? "auth_failed" : null,
      reason: `strike_${failures}_of_${REFRESH_STRIKE_LIMIT}`,
      durationMs: Date.now() - startedAt,
      detail: error instanceof Error ? error.message : String(error),
    });
    if (giveUp) {
      await emitConnectionBroken(db, row.status, row);
      await trackBroken(env, db, row.status, row);
    }
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
          // A dead grant is never retried — but *only* a dead grant. This
          // used to exclude every `auth_failed` row, which meant one
          // rejected data request stopped the token being refreshed ever
          // again: the row kept a valid refresh token, nothing used it, and
          // the access token lapsed hours later with the refresh machinery
          // looking broken when it had simply never been asked.
          isNull(integrationTable.reauthRequiredAt),
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
