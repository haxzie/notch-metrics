import { Hono } from "hono";
import { and, eq } from "drizzle-orm";
import { connectionName, getAdapter } from "@notch/integrations";
import { IntegrationCreate, IntegrationUpdate } from "@notch/schemas";
import { integration as integrationTable } from "@notch/db";
import { authenticate, rateLimited, sessionOnly, type AppContext } from "../middleware.ts";
import { seedSubscriptions } from "../lib/notifications.ts";
import { fingerprint, sealCredentials } from "../lib/crypto.ts";
import { openFreshCredentials } from "../lib/token-refresh.ts";
import { callRecorder, recordEvent } from "../lib/events.ts";
import { adapterContext, toMetricError } from "../lib/adapter.ts";
import { id } from "../lib/ids.ts";
import { loadUser } from "../lib/identity.ts";
import { track } from "../lib/track.ts";
import { logError } from "../lib/redact.ts";
import type { Database } from "../lib/db.ts";

export const integrations = new Hono<AppContext>();

integrations.use("*", authenticate);

/**
 * The only shape this route will ever return.
 *
 * There is no branch anywhere that includes the ciphertext, which is why a bug
 * in a handler cannot leak it. `credentialHint` is first-eight-last-four.
 */
function toPublic(row: typeof integrationTable.$inferSelect) {
  return {
    id: row.id,
    provider: row.provider,
    label: row.label,
    status: row.status,
    credentialHint: row.credentialHint,
    accountLabel: row.accountLabel,
    accountCurrency: row.accountCurrency,
    enabledMetrics: row.enabledMetrics ?? [],
    availableMetrics: row.availableMetrics ?? [],
    lastSyncedAt: row.lastSyncedAt?.toISOString() ?? null,
    lastErrorAt: row.lastErrorAt?.toISOString() ?? null,
    lastErrorCode: row.lastErrorCode,
    createdAt: row.createdAt.toISOString(),
  };
}

/**
 * Loads an integration, scoped to the caller.
 *
 * Callers answer 404 rather than 403 when this returns null: a 403 confirms
 * that somebody else's integration id exists, which is a membership oracle over
 * an enumerable id space.
 */
async function owned(
  db: Database,
  userId: string,
  rowId: string,
): Promise<typeof integrationTable.$inferSelect | null> {
  const rows = await db
    .select()
    .from(integrationTable)
    .where(and(eq(integrationTable.id, rowId), eq(integrationTable.userId, userId)))
    .limit(1);
  return rows[0] ?? null;
}

integrations.get("/", async (c) => {
  const rows = await c
    .get("db")
    .select()
    .from(integrationTable)
    .where(eq(integrationTable.userId, c.get("identity").userId));
  return c.json(rows.map(toPublic));
});

integrations.post("/", sessionOnly, rateLimited({ limit: 20, windowSeconds: 3600 }), async (c) => {
  const body = IntegrationCreate.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ code: "BAD_REQUEST", message: "Invalid request." }, 400);

  const db = c.get("db");
  const userId = c.get("identity").userId;
  const adapter = getAdapter(body.data.provider);

  const credentials = adapter.credentialSchema.safeParse(body.data.credentials);
  if (!credentials.success) {
    return c.json(
      {
        code: "BAD_CREDENTIALS",
        message: credentials.error.issues[0]?.message ?? "Invalid credentials.",
      },
      400,
    );
  }

  const user = await loadUser(db, userId);
  if (!user) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  // Verify *before* writing anything. A key that does not work must not become
  // a row that silently never syncs and shows a zero for a week.
  let verified;
  try {
    verified = await adapter.verify(
      adapterContext({
        provider: body.data.provider,
        timeZone: user.timezone,
        preferredCurrency: user.preferredCurrency,
        signal: AbortSignal.timeout(15_000),
      }),
      credentials.data,
    );
  } catch (error) {
    logError("integrations.verify", error);
    const mapped = toMetricError(error);
    return c.json({ code: mapped.code, message: mapped.message }, 400);
  }

  const fp = await fingerprint(credentials.data as Record<string, string>);
  const existing = await db
    .select({ id: integrationTable.id })
    .from(integrationTable)
    .where(
      and(
        eq(integrationTable.userId, userId),
        eq(integrationTable.provider, body.data.provider),
        eq(integrationTable.credentialFingerprint, fp),
      ),
    )
    .limit(1);
  if (existing[0]) {
    return c.json({ code: "ALREADY_CONNECTED", message: "That key is already connected." }, 409);
  }

  const existingLabels = (
    await db
      .select({ label: integrationTable.label })
      .from(integrationTable)
      .where(eq(integrationTable.userId, userId))
  ).map((r) => r.label);

  const rowId = id("int");
  const sealed = await sealCredentials(
    c.env,
    { userId, integrationId: rowId, provider: body.data.provider },
    credentials.data as Record<string, string>,
  );

  await db.insert(integrationTable).values({
    id: rowId,
    userId,
    provider: body.data.provider,
    label:
      body.data.label ??
      connectionName({
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
    // Random, so the five-minute cron does not try every integration in the
    // account on the same tick and fan out into one burst at the provider.
    refreshOffsetSeconds: Math.floor(Math.random() * 300),
  });

  // The connection's notification toggles, from its manifest's defaults. Seeded
  // here as well as on first read of /settings, so a brand-new connection can
  // notify before anybody has opened the settings pane.
  await seedSubscriptions(db, userId, rowId, body.data.provider);

  const row = await owned(db, userId, rowId);
  if (row) {
    await track(
      c.env,
      {
        kind: "integration_connected",
        userId: row.userId,
        email: user.email,
        provider: row.provider,
        account: row.accountLabel ?? row.label,
        integrationId: row.id,
      },
      c.executionCtx.waitUntil.bind(c.executionCtx),
    );
  }
  return row
    ? c.json(toPublic(row), 201)
    : c.json({ code: "ERROR", message: "Could not save." }, 500);
});

// Renaming and disconnecting are reachable with a device token, unlike
// creating. The desktop app is where people manage their connections, and
// sending them to a browser to delete one is the kind of friction that makes
// a stale credential sit there failing for months.
//
// Creating stays session-only: that is the one route that accepts raw
// provider credentials, and the app deliberately never handles those — the
// connect-link flow exists so a native window never asks for a Stripe key.
// A stolen device token can therefore destroy a connection but never read or
// create one, and `DELETE /v1/me/devices/:id` revokes it.
integrations.patch("/:id", async (c) => {
  const row = await owned(c.get("db"), c.get("identity").userId, c.req.param("id"));
  // 404, not 403. A 403 confirms that somebody else's integration id exists.
  if (!row) return c.json({ code: "NOT_FOUND", message: "No such integration." }, 404);

  const body = IntegrationUpdate.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ code: "BAD_REQUEST", message: "Invalid request." }, 400);

  const patch: Partial<typeof integrationTable.$inferInsert> = { updatedAt: new Date() };
  if (body.data.label) patch.label = body.data.label;
  if (body.data.enabledMetrics) patch.enabledMetrics = body.data.enabledMetrics;
  if (body.data.disabled !== undefined) patch.status = body.data.disabled ? "disabled" : "ok";

  if (body.data.credentials) {
    // The one part of this route that still needs a browser session.
    // Replacing credentials is creating a connection by another name, and
    // the app has no business carrying a provider key.
    if (c.get("identity").kind !== "session") {
      return c.json(
        { code: "SESSION_REQUIRED", message: "Replacing credentials must be done on the web." },
        403,
      );
    }
    const adapter = getAdapter(row.provider);
    const credentials = adapter.credentialSchema.safeParse(body.data.credentials);
    if (!credentials.success) {
      return c.json({ code: "BAD_CREDENTIALS", message: "Invalid credentials." }, 400);
    }
    // Re-sealed under whatever the *currently active* KEK is, so updating a key
    // quietly migrates that row forward.
    const sealed = await sealCredentials(
      c.env,
      { userId: row.userId, integrationId: row.id, provider: row.provider },
      credentials.data as Record<string, string>,
    );
    Object.assign(patch, {
      credentialCiphertext: sealed.ciphertext,
      credentialIv: sealed.iv,
      credentialWrappedDek: sealed.wrappedDek,
      keyVersion: sealed.keyVersion,
      credentialHint: sealed.hint,
      credentialFingerprint: sealed.fingerprint,
      status: "ok",
      failureCount: 0,
      authFailures: 0,
      // A new credential is a new grant. Leaving this set would keep the
      // row out of the refresh sweep for the lifetime of the connection.
      reauthRequiredAt: null,
      disabledUntil: 0,
      lastErrorCode: null,
    });
  }

  await c.get("db").update(integrationTable).set(patch).where(eq(integrationTable.id, row.id));
  const updated = await owned(c.get("db"), row.userId, row.id);
  return updated ? c.json(toPublic(updated)) : c.json({ code: "ERROR", message: "Gone." }, 500);
});

integrations.delete("/:id", async (c) => {
  const db = c.get("db");
  const row = await owned(db, c.get("identity").userId, c.req.param("id"));
  if (!row) return c.json({ code: "NOT_FOUND", message: "No such integration." }, 404);
  // Read before the delete: afterwards there is no row to name, and a
  // notification saying only that *something* was disconnected is not worth
  // the channel it is posted to.
  const owner = await loadUser(db, row.userId);
  await db.delete(integrationTable).where(eq(integrationTable.id, row.id));
  await track(
    c.env,
    {
      kind: "integration_disconnected",
      userId: row.userId,
      email: owner?.email ?? null,
      provider: row.provider,
      account: row.accountLabel ?? row.label,
      integrationId: row.id,
    },
    c.executionCtx.waitUntil.bind(c.executionCtx),
  );
  return c.json({ ok: true });
});

integrations.post("/:id/verify", sessionOnly, async (c) => {
  const row = await owned(c.get("db"), c.get("identity").userId, c.req.param("id"));
  if (!row) return c.json({ code: "NOT_FOUND", message: "No such integration." }, 404);

  const db = c.get("db");
  const user = await loadUser(db, row.userId);
  if (!user) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  const adapter = getAdapter(row.provider);
  const { credentials } = await openFreshCredentials(c.env, db, row);
  const recorder = callRecorder();
  const startedAt = Date.now();

  try {
    const verified = await adapter.verify(
      adapterContext({
        provider: row.provider,
        timeZone: user.timezone,
        preferredCurrency: user.preferredCurrency,
        signal: AbortSignal.timeout(15_000),
        onCall: recorder.onCall,
      }),
      credentials,
    );
    await db
      .update(integrationTable)
      .set({
        status: "ok",
        failureCount: 0,
        authFailures: 0,
        reauthRequiredAt: null,
        disabledUntil: 0,
        lastErrorCode: null,
        accountLabel: verified.accountLabel,
        accountCurrency: verified.currency,
        availableMetrics: verified.availableMetrics,
      })
      .where(eq(integrationTable.id, row.id));

    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "verify",
      outcome: "ok",
      durationMs: Date.now() - startedAt,
      calls: recorder.calls,
      httpStatus: recorder.lastStatus(),
    });

    return c.json({ ok: true, ...verified, code: null, message: null });
  } catch (error) {
    logError(`integrations.reverify.${row.id}`, error);
    const mapped = toMetricError(error);
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "verify",
      outcome: "error",
      code: mapped.code,
      httpStatus: recorder.lastStatus(),
      durationMs: Date.now() - startedAt,
      calls: recorder.calls,
      detail: error instanceof Error ? error.message : String(error),
    });
    await db
      .update(integrationTable)
      .set({
        status: mapped.code === "auth_failed" ? "auth_failed" : row.status,
        lastErrorCode: mapped.code,
        lastErrorAt: new Date(),
      })
      .where(eq(integrationTable.id, row.id));

    return c.json({
      ok: false,
      accountLabel: null,
      currency: null,
      availableMetrics: [],
      code: mapped.code,
      message: mapped.message,
    });
  }
});
