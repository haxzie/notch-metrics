import { createExecutionContext, env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { connectLink, integration, user } from "@notch/db";
import { eq } from "drizzle-orm";
import worker from "../src/index.ts";
import { id, randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(connectLink);
  await db().delete(integration);
  await db().delete(user);
});
afterEach(() => vi.unstubAllGlobals());

const ctx = createExecutionContext();

function call(path: string, init?: RequestInit) {
  return worker.fetch(new Request(`http://localhost:8787${path}`, init), env, ctx);
}

function submit(token: string, body: Record<string, string>) {
  return call(`/v1/link/${token}/submit`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

/** Mints a link the way `POST /v1/connect/:id` does. */
async function makeLink(userId: string, connectorId = "stripe", ageMs = 0) {
  const token = randomToken();
  await db()
    .insert(connectLink)
    .values({
      id: id("lnk"),
      userId,
      connectorId,
      tokenHash: await sha256Base64Url(token),
      expiresAt: new Date(Date.now() + 10 * 60_000 - ageMs),
    });
  return token;
}

/** Stripe answering `/account` and `/subscriptions` for a key we accept. */
function stubStripe(options: { ok?: boolean } = {}) {
  const ok = options.ok ?? true;
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    const url = String(input instanceof Request ? input.url : input);
    if (!ok) {
      return new Response(JSON.stringify({ error: { message: "Invalid API Key" } }), {
        status: 401,
        headers: { "content-type": "application/json" },
      });
    }
    const body = url.includes("/v1/account")
      ? { id: "acct_123", default_currency: "usd", business_profile: { name: "Acme Inc" } }
      : { data: [], has_more: false };
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  });
}

const GOOD_KEY = "sk_test_51Abcdefghijklmnopqrstuvwx";

describe("GET /v1/link/:token", () => {
  it("describes the connector and only the fields a human types", async () => {
    const u = await makeUser();
    const response = await call(`/v1/link/${await makeLink(u.id)}`);
    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      connector: { id: string; name: string; fields: { key: string; type: string }[] };
    };
    expect(body.connector.id).toBe("stripe");
    expect(body.connector.fields.map((f) => f.key)).toContain("secret_key");
    expect(scalar(body.connector.fields.find((f) => f.key === "secret_key")).type).toBe("secret");
  });

  it("gives one answer for unknown, expired and already-used links", async () => {
    const u = await makeUser();
    const expired = await makeLink(u.id, "stripe", 11 * 60_000);

    const unknown = await call(`/v1/link/${randomToken()}`);
    const stale = await call(`/v1/link/${expired}`);

    expect(unknown.status).toBe(404);
    expect(stale.status).toBe(404);
    // Identical bodies: a different message tells somebody probing tokens
    // which of their guesses actually existed.
    expect(await unknown.json()).toEqual(await stale.json());
  });
});

describe("POST /v1/link/:token/submit", () => {
  it("verifies, stores and burns the link", async () => {
    stubStripe();
    const u = await makeUser();
    const token = await makeLink(u.id);

    const response = await submit(token, { secret_key: GOOD_KEY });
    expect(response.status).toBe(200);

    const body = (await response.json()) as { accountLabel: string; returnTo: string };
    expect(body.accountLabel).toBe("Acme Inc");
    expect(body.returnTo).toBe("notchmetrics://connected?provider=stripe");

    const rows = await db().select().from(integration).where(eq(integration.userId, u.id));
    const row = scalar(rows[0]);
    expect(row.provider).toBe("stripe");
    expect(row.accountCurrency).toBe("USD");
    // The plaintext key must not survive anywhere on the row.
    expect(JSON.stringify(row)).not.toContain(GOOD_KEY);

    // Single-use: a replayed submission cannot create a second integration.
    const replay = await submit(token, { secret_key: GOOD_KEY });
    expect(replay.status).toBe(404);
    expect(await db().select().from(integration)).toHaveLength(1);
  });

  it("writes no row when the provider rejects the key", async () => {
    stubStripe({ ok: false });
    const u = await makeUser();
    const token = await makeLink(u.id);

    const response = await submit(token, { secret_key: GOOD_KEY });
    expect(response.status).toBe(400);
    expect(await db().select().from(integration)).toHaveLength(0);

    // The link survives a failed attempt, so the user can correct a typo
    // rather than going back to the app for a fresh link.
    const stillLive = await call(`/v1/link/${token}`);
    expect(stillLive.status).toBe(200);
  });

  it("rejects a field the form never showed", async () => {
    stubStripe();
    const u = await makeUser();
    const token = await makeLink(u.id);

    // `userId` is not a declared input field; it must be dropped before the
    // credential schema sees it, not merged into the stored blob.
    const response = await submit(token, { secret_key: GOOD_KEY, userId: "usr_someone_else" });
    expect(response.status).toBe(200);

    const row = scalar((await db().select().from(integration))[0]);
    expect(row.userId).toBe(u.id);
  });

  it("refuses the API-key path for an OAuth connector", async () => {
    const u = await makeUser();
    const token = await makeLink(u.id, "google-analytics");

    const response = await submit(token, { propertyId: "123" });
    expect(response.status).toBe(400);
    expect((await response.json()) as { code: string }).toMatchObject({ code: "WRONG_FLOW" });
  });
});
