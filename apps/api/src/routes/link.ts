import { Hono } from "hono";
import type { Context } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import { and, eq, isNull } from "drizzle-orm";
import { connectionName, getAdapter } from "@notch/integrations";
import type { VerifyResult } from "@notch/integrations";
import { connectLink, integration as integrationTable } from "@notch/db";
import { type AppContext, rateLimitedByIp } from "../middleware.ts";
import { fingerprint, openCredentials, sealCredentials } from "../lib/crypto.ts";
import { adapterContext, toMetricError } from "../lib/adapter.ts";
import { id, randomToken, sha256Base64Url } from "../lib/ids.ts";
import { loadUser } from "../lib/identity.ts";
import { track } from "../lib/track.ts";
import { logError } from "../lib/redact.ts";
import { seedSubscriptions } from "../lib/notifications.ts";

/**
 * The public half of the connect flow — what the browser talks to.
 *
 * Unauthenticated by design: the person completing this is in a browser that
 * has never seen the desktop app's token. The link token *is* the
 * authorisation, which is why it is short-lived, single-use, and stored
 * hashed.
 */
export const link = new Hono<AppContext>();

type Database = AppContext["Variables"]["db"];

async function resolve(db: Database, token: string) {
  const rows = await db
    .select()
    .from(connectLink)
    .where(
      and(eq(connectLink.tokenHash, await sha256Base64Url(token)), isNull(connectLink.completedAt)),
    )
    .limit(1);

  const row = rows[0];
  if (!row || row.expiresAt.getTime() < Date.now()) return null;
  return row;
}

/** What the connect page renders. */
link.get("/:token", rateLimitedByIp(60, 600), async (c) => {
  const row = await resolve(c.get("db"), c.req.param("token"));
  // One message for expired, unknown and already-used. Distinguishing them
  // tells somebody probing tokens which guesses were close.
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const adapter = getAdapter(row.connectorId);
  const visible = adapter.userInputFields;

  return c.json({
    connector: {
      id: adapter.manifest.id,
      name: adapter.manifest.name,
      tagline: adapter.manifest.tagline,
      docsUrl: adapter.manifest.docsUrl,
      accentColor: adapter.manifest.accentColor,
      authMode: adapter.manifest.authMode,
      // Null rather than omitted, so the page branches on one falsy check
      // instead of distinguishing "no steps" from "an older API that did not
      // send them".
      setupSteps: adapter.manifest.setupSteps ?? null,
      // Only fields a human is meant to type. An OAuth connector's token
      // columns live in the same credential blob and must never be rendered
      // as a form input.
      fields: adapter.manifest.fields.filter(
        (f) => visible === undefined || visible.includes(f.key),
      ),
    },
    expiresAt: row.expiresAt.toISOString(),
  });
});

/** The API-key path: the browser posts what the user typed. */
link.post("/:token/submit", rateLimitedByIp(20, 600), async (c) => {
  const row = await resolve(c.get("db"), c.req.param("token"));
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const adapter = getAdapter(row.connectorId);
  if (adapter.manifest.authMode !== "api_key") {
    return c.json({ code: "WRONG_FLOW", message: "This connector uses OAuth." }, 400);
  }

  const body = await c.req.json<Record<string, string>>().catch(() => ({}));
  const visible = new Set(adapter.userInputFields ?? Object.keys(body));
  // Only declared input fields are accepted. Without this filter a crafted
  // submission could set a field the form never showed.
  const submitted = Object.fromEntries(Object.entries(body).filter(([key]) => visible.has(key)));

  const credentials = adapter.credentialSchema.safeParse(submitted);
  if (!credentials.success) {
    return c.json(
      {
        code: "BAD_CREDENTIALS",
        message: credentials.error.issues[0]?.message ?? "Those details are not valid.",
      },
      400,
    );
  }

  const db = c.get("db");
  const user = await loadUser(db, row.userId);
  if (!user) return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);

  // Verified before anything is written. A key that does not work must not
  // become a row that silently never syncs.
  let verified;
  try {
    verified = await adapter.verify(
      adapterContext({
        provider: row.connectorId,
        timeZone: user.timezone,
        preferredCurrency: user.preferredCurrency,
        signal: AbortSignal.timeout(15_000),
      }),
      credentials.data as Record<string, string>,
    );
  } catch (error) {
    logError("link.verify", error);
    const mapped = toMetricError(error);
    return c.json({ code: mapped.code, message: mapped.message }, 400);
  }

  const result = await finishConnection(
    c,
    row,
    credentials.data as Record<string, string>,
    verified,
  );
  if ("error" in result) return c.json(result.error, result.status);
  return c.json(result.body);
});

/**
 * Everything after "these credentials work": seal them, write the row, burn
 * the link.
 *
 * Shared by the API-key submit and the OAuth callback rather than written
 * twice. The two paths differ only in where the credentials came from, and
 * the half that is easy to get subtly wrong — the AAD scope, the duplicate
 * check, the naming, burning the link — is the half they have in common.
 */
async function finishConnection(
  c: Context<AppContext>,
  row: { id: string; userId: string; connectorId: string },
  credentials: Record<string, string>,
  verified: VerifyResult,
): Promise<
  | { body: { ok: true; integrationId: string; accountLabel: string | null; returnTo: string } }
  | { error: { code: string; message: string }; status: 404 | 409 }
> {
  const db = c.get("db");
  const adapter = getAdapter(row.connectorId);

  const integrationId = id("int");
  const sealed = await sealCredentials(
    c.env,
    { userId: row.userId, integrationId, provider: row.connectorId },
    credentials,
  );

  const fp = await fingerprint(credentials);
  const existing = await db
    .select({ id: integrationTable.id })
    .from(integrationTable)
    .where(
      and(
        eq(integrationTable.userId, row.userId),
        eq(integrationTable.provider, row.connectorId),
        eq(integrationTable.credentialFingerprint, fp),
      ),
    )
    .limit(1);
  if (existing[0]) {
    return {
      error: { code: "ALREADY_CONNECTED", message: "That account is already connected." },
      status: 409,
    };
  }

  // Named from what verify() learned, disambiguated against this user's
  // existing connections — two Stripe accounts with no business name set
  // would otherwise both read "Stripe".
  const existingLabels = (
    await db
      .select({ label: integrationTable.label })
      .from(integrationTable)
      .where(eq(integrationTable.userId, row.userId))
  ).map((r) => r.label);

  await db.insert(integrationTable).values({
    id: integrationId,
    userId: row.userId,
    provider: row.connectorId,
    label: connectionName({
      manifest: adapter.manifest,
      accountLabel: verified.accountLabel,
      taken: existingLabels,
    }),
    credentialCiphertext: sealed.ciphertext,
    credentialIv: sealed.iv,
    credentialWrappedDek: sealed.wrappedDek,
    keyVersion: sealed.keyVersion,
    credentialHint: sealed.hint,
    credentialFingerprint: sealed.fingerprint,
    enabledMetrics: verified.availableMetrics,
    availableMetrics: verified.availableMetrics,
    accountLabel: verified.accountLabel,
    accountCurrency: verified.currency,
    refreshOffsetSeconds: Math.floor(Math.random() * 300),
  });

  // See the note at the other insert site: the toggles come from the manifest
  // the moment the connection exists.
  await seedSubscriptions(db, row.userId, integrationId, row.connectorId);

  // Single-use, and the pending tokens go with it: burning the link here
  // means a replayed submission cannot create a second integration, and no
  // row is left holding a decryptable access token after the flow is over.
  await db
    .update(connectLink)
    .set({
      completedAt: new Date(),
      integrationId,
      pendingCiphertext: null,
      pendingIv: null,
      pendingWrappedDek: null,
      pendingKeyVersion: null,
    })
    .where(eq(connectLink.id, row.id));

  // One notification for both halves of the flow. The OAuth callback and the
  // API-key submit meet here, so hooking the routes instead would be the same
  // line written twice and forgotten once.
  const owner = await loadUser(db, row.userId);
  await track(
    c.env,
    {
      kind: "integration_connected",
      userId: row.userId,
      email: owner?.email ?? null,
      provider: row.connectorId,
      account: verified.accountLabel ?? row.connectorId,
      integrationId,
    },
    c.executionCtx.waitUntil.bind(c.executionCtx),
  );

  return {
    body: {
      ok: true,
      integrationId,
      accountLabel: verified.accountLabel,
      // Where to send the browser so the app knows to refresh.
      returnTo: `notchmetrics://connected?provider=${encodeURIComponent(row.connectorId)}`,
    },
  };
}
