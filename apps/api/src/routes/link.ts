import { Hono } from "hono";
import type { Context } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import { and, eq, isNull } from "drizzle-orm";
import { connectionName, getAdapter, oauthSecretNames } from "@notch/integrations";
import type { VerifyResult } from "@notch/integrations";
import { connectLink, integration as integrationTable } from "@notch/db";
import { type AppContext, rateLimitedByIp } from "../middleware.ts";
import { fingerprint, openCredentials, sealCredentials } from "../lib/crypto.ts";
import { adapterContext, toMetricError } from "../lib/adapter.ts";
import { id, randomToken, sha256Base64Url } from "../lib/ids.ts";
import { loadUser } from "../lib/identity.ts";
import { logError } from "../lib/redact.ts";

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

/**
 * The OAuth callback carries `state` and nothing else of ours — GitHub will
 * not hand back a path parameter — so the row is found by state.
 *
 * Stored hashed for the same reason the link token is: it travels in a URL,
 * through the provider and into browser history, and on the way back it is
 * the only thing identifying which pending connection this is.
 */
async function resolveByState(db: Database, state: string) {
  const rows = await db
    .select()
    .from(connectLink)
    .where(
      and(
        eq(connectLink.oauthState, await sha256Base64Url(state)),
        isNull(connectLink.completedAt),
      ),
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
      oauth: adapter.manifest.oauth ?? null,
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

  // Single-use, and the pending tokens go with it: burning the link here
  // means a replayed submission cannot create a second integration, and no
  // row is left holding a decryptable access token after the flow is over.
  await db
    .update(connectLink)
    .set({
      completedAt: new Date(),
      integrationId,
      oauthState: null,
      pendingCiphertext: null,
      pendingIv: null,
      pendingWrappedDek: null,
      pendingKeyVersion: null,
    })
    .where(eq(connectLink.id, row.id));

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

/**
 * Which connect page to come back to, remembered across the provider.
 *
 * The link token cannot ride along in `state` — that goes to the provider —
 * and it is stored hashed, so the callback cannot recover it from the row
 * either. A cookie on the API's own origin carries it instead: the callback
 * is a top-level navigation, so `SameSite=Lax` is sent, and the token is
 * already in this browser's address bar so the cookie reveals nothing new.
 */
const LINK_COOKIE = "nm_connect_link";

/** Where GitHub (and every later OAuth connector) is told to come back to. */
function redirectUri(c: Context<AppContext>): string {
  return `${c.env.API_URL}/v1/link/oauth/callback`;
}

function oauthClient(c: Context<AppContext>, connectorId: string) {
  const names = oauthSecretNames(connectorId as Parameters<typeof oauthSecretNames>[0]);
  const clientId = (c.env as unknown as Record<string, string | undefined>)[names.clientId];
  const clientSecret = (c.env as unknown as Record<string, string | undefined>)[names.clientSecret];
  if (!clientId || !clientSecret) return null;
  return { clientId, clientSecret };
}

/**
 * Start the grant: mint a state, remember its hash, redirect.
 *
 * A 302 rather than JSON with a URL in it. The browser has to leave this
 * origin for the provider's, and a page that fetches the URL and then
 * assigns `location` is the same journey with one more place for a popup
 * blocker or a CSP to break it.
 */
link.get("/:token/authorize", rateLimitedByIp(20, 600), async (c) => {
  const db = c.get("db");
  const token = c.req.param("token");

  // This URL is reached by a human clicking a button, so every answer from
  // here is a redirect carrying the message — a JSON error object rendered
  // raw in the address bar is where the flow dies with nothing to click.
  const back = (message: string) =>
    c.redirect(
      `${c.env.APP_URL}/connect/${encodeURIComponent(token)}?${new URLSearchParams({ error: message })}`,
      302,
    );

  const row = await resolve(db, token);
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const adapter = getAdapter(row.connectorId);
  if (adapter.manifest.authMode !== "oauth2" || !adapter.oauth) {
    return back("This connector is connected with an API key, not a sign-in.");
  }

  const client = oauthClient(c, row.connectorId);
  if (!client) {
    // Named plainly rather than left as a 500. A missing client id is a
    // deployment that was never finished, and the message has to be enough
    // to act on without reading a log nobody has.
    return back(`Connecting ${adapter.manifest.name} is not set up on this server yet.`);
  }

  const state = randomToken(32);
  await db
    .update(connectLink)
    .set({ oauthState: await sha256Base64Url(state) })
    .where(eq(connectLink.id, row.id));

  setCookie(c, LINK_COOKIE, token, {
    httpOnly: true,
    sameSite: "Lax",
    secure: new URL(c.env.API_URL).protocol === "https:",
    path: "/v1/link",
    maxAge: 600,
  });

  return c.redirect(
    adapter.oauth.authorizationUrl({
      clientId: client.clientId,
      redirectUri: redirectUri(c),
      state,
    }),
    302,
  );
});

/**
 * The provider's return leg.
 *
 * Always ends in a redirect back to the connect page rather than in JSON:
 * this URL is reached by a human's browser following the provider's
 * redirect, and a raw error object in the address bar is where the flow dies
 * silently.
 */
link.get("/oauth/callback", rateLimitedByIp(40, 600), async (c) => {
  const db = c.get("db");
  const state = c.req.query("state") ?? "";
  const code = c.req.query("code") ?? "";

  const row = state ? await resolveByState(db, state) : null;
  // No row means an unknown, expired or already-used state. There is no
  // connect page to return to, so this is the one branch that answers
  // directly.
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const token = getCookie(c, LINK_COOKIE) ?? "";
  deleteCookie(c, LINK_COOKIE, { path: "/v1/link" });
  const back = (params: Record<string, string>) =>
    c.redirect(
      `${c.env.APP_URL}/connect/${encodeURIComponent(token)}?${new URLSearchParams(params)}`,
      302,
    );

  // The user pressed Cancel on the provider's consent screen. Not an error.
  if (!code) {
    await db.update(connectLink).set({ oauthState: null }).where(eq(connectLink.id, row.id));
    return back({ cancelled: "1" });
  }

  const adapter = getAdapter(row.connectorId);
  const client = oauthClient(c, row.connectorId);
  if (!adapter.oauth || !client) {
    return c.json({ code: "NOT_CONFIGURED", message: "This connector is not configured." }, 503);
  }

  let credentials: Record<string, string>;
  try {
    credentials = (await adapter.oauth.exchangeCode({
      code,
      redirectUri: redirectUri(c),
      clientId: client.clientId,
      clientSecret: client.clientSecret,
    })) as Record<string, string>;
  } catch (error) {
    logError("link.oauth.exchange", error);
    return back({ error: toMetricError(error).message });
  }

  const user = await loadUser(db, row.userId);
  if (!user) return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);

  // Nothing left to choose: verify and finish in one go.
  if (!adapter.manifest.oauth?.requiresSelection) {
    try {
      const verified = await adapter.verify(
        adapterContext({
          provider: row.connectorId,
          timeZone: user.timezone,
          preferredCurrency: user.preferredCurrency,
          signal: AbortSignal.timeout(15_000),
        }),
        credentials,
      );
      const result = await finishConnection(c, row, credentials, verified);
      if ("error" in result) return back({ error: result.error.message });
      return c.redirect(result.body.returnTo, 302);
    } catch (error) {
      logError("link.oauth.verify", error);
      return back({ error: toMetricError(error).message });
    }
  }

  // Held, encrypted, until the user picks. The tokens are a live credential
  // from this moment on, so they are sealed with the same envelope a
  // finished integration uses — scoped to this link, so a blob copied to
  // another row does not decrypt.
  const sealed = await sealCredentials(
    c.env,
    { userId: row.userId, integrationId: row.id, provider: row.connectorId },
    credentials,
  );
  await db
    .update(connectLink)
    .set({
      pendingCiphertext: sealed.ciphertext,
      pendingIv: sealed.iv,
      pendingWrappedDek: sealed.wrappedDek,
      pendingKeyVersion: sealed.keyVersion,
    })
    .where(eq(connectLink.id, row.id));

  return back({ step: "select" });
});

/** Reads the pending tokens back out, or null when there are none. */
async function pendingCredentials(
  c: Context<AppContext>,
  row: {
    id: string;
    userId: string;
    connectorId: string;
    pendingCiphertext: string | null;
    pendingIv: string | null;
    pendingWrappedDek: string | null;
    pendingKeyVersion: number | null;
  },
): Promise<Record<string, string> | null> {
  if (
    !row.pendingCiphertext ||
    !row.pendingIv ||
    !row.pendingWrappedDek ||
    row.pendingKeyVersion === null
  ) {
    return null;
  }
  return openCredentials(
    c.env,
    { userId: row.userId, integrationId: row.id, provider: row.connectorId },
    {
      ciphertext: row.pendingCiphertext,
      iv: row.pendingIv,
      wrappedDek: row.pendingWrappedDek,
      keyVersion: row.pendingKeyVersion,
    },
  );
}

/** What the user chooses between after authorising — repositories, properties, sites. */
link.get("/:token/options", rateLimitedByIp(30, 600), async (c) => {
  const row = await resolve(c.get("db"), c.req.param("token"));
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const adapter = getAdapter(row.connectorId);
  const selection = adapter.oauth?.selection;
  if (!selection) {
    return c.json({ code: "WRONG_FLOW", message: "There is nothing to choose here." }, 400);
  }

  const credentials = await pendingCredentials(c, row);
  if (!credentials) {
    return c.json({ code: "NOT_AUTHORISED", message: "Authorise the connection first." }, 409);
  }

  try {
    return c.json({ label: selection.label, options: await selection.options(credentials) });
  } catch (error) {
    logError("link.oauth.options", error);
    const mapped = toMetricError(error);
    return c.json({ code: mapped.code, message: mapped.message }, 400);
  }
});

/** The user picked. Fill the field in, verify, and finish. */
link.post("/:token/select", rateLimitedByIp(20, 600), async (c) => {
  const row = await resolve(c.get("db"), c.req.param("token"));
  if (!row) {
    return c.json({ code: "INVALID_LINK", message: "This link is no longer valid." }, 404);
  }

  const adapter = getAdapter(row.connectorId);
  const selection = adapter.oauth?.selection;
  if (!selection) {
    return c.json({ code: "WRONG_FLOW", message: "There is nothing to choose here." }, 400);
  }

  const held = await pendingCredentials(c, row);
  if (!held) {
    return c.json({ code: "NOT_AUTHORISED", message: "Authorise the connection first." }, 409);
  }

  const body = await c.req.json<{ value?: string }>().catch(() => ({}) as { value?: string });
  // Checked against the provider's own list rather than trusted. The value
  // lands in a credential blob and then in every API path this adapter
  // builds, and "owner/name" from a POST body is not a promise about what
  // the grant covers.
  let offered;
  try {
    offered = await selection.options(held);
  } catch (error) {
    logError("link.oauth.options", error);
    return c.json({ code: "PROVIDER_ERROR", message: toMetricError(error).message }, 400);
  }
  const chosen = offered.find((option) => option.value === body.value);
  if (!chosen) {
    return c.json({ code: "BAD_SELECTION", message: "That is not one of the choices." }, 400);
  }

  const merged = { ...held, [selection.field]: chosen.value };
  const credentials = adapter.credentialSchema.safeParse(merged);
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
    logError("link.oauth.verify", error);
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
