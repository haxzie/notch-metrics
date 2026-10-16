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

/**
 * The OAuth leg.
 *
 * Two shapes, and both are covered because the difference is where a flow
 * can go wrong. GitHub finishes at the callback — the grant *is* the
 * connection, and which repository a tile counts is settled per widget.
 * Search Console still pauses on a choice, which is the path that holds a
 * live token encrypted between two requests.
 */
describe("link / oauth", () => {
  function stubGitHub(options: { exchange?: unknown; repos?: unknown; status?: number } = {}) {
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input instanceof Request ? input.url : input);
      const json = (body: unknown, status = 200) =>
        new Response(JSON.stringify(body), {
          status,
          headers: { "content-type": "application/json" },
        });

      if (url.includes("login/oauth/access_token")) {
        return json(options.exchange ?? { access_token: "gho_token", scope: "repo" });
      }
      // Before the `/repos/` branch: `verify` now reads the account, which is
      // what names the connection since the repository moved onto the widget.
      if (url.endsWith("/user")) {
        return json({ login: "haxzie", followers: 128 });
      }
      if (url.includes("/user/repos")) {
        return json(
          options.repos ?? [
            { full_name: "haxzie/notch-metrics", stargazers_count: 412, private: false },
            { full_name: "haxzie/other", stargazers_count: 3, private: false },
          ],
        );
      }
      if (url.includes("/repos/")) {
        return json(
          {
            full_name: "haxzie/notch-metrics",
            stargazers_count: 412,
            forks_count: 37,
            open_issues_count: 23,
            private: false,
          },
          options.status ?? 200,
        );
      }
      throw new Error(`unexpected fetch to ${url}`);
    });
  }

  /** Google's token endpoint and the Search Console property list. */
  function stubGoogle() {
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input instanceof Request ? input.url : input);
      const json = (body: unknown) =>
        new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });

      if (url.includes("oauth2.googleapis.com/token")) {
        // Both long enough for the credential schema's minimums — a short one
        // here fails the parse at the end of the flow and reads as a broken
        // selection rather than a broken fixture.
        return json({
          access_token: "ya29.access-token-value",
          refresh_token: "1//refresh-token-value",
          expires_in: 3599,
        });
      }
      if (url.includes("/webmasters/v3/sites")) {
        return json({
          siteEntry: [{ siteUrl: "sc-domain:example.com", permissionLevel: "siteOwner" }],
        });
      }
      throw new Error(`unexpected fetch to ${url}`);
    });
  }

  /** The env the Worker sees has no connector client unless a test adds one. */
  const withClient = {
    ...env,
    OAUTH_GITHUB_CLIENT_ID: "Ov23liTEST",
    OAUTH_GITHUB_CLIENT_SECRET: "secret",
  };

  function callWith(path: string, e: typeof env, init?: RequestInit) {
    return worker.fetch(new Request(`http://localhost:8787${path}`, init), e, ctx);
  }

  it("says so plainly when the server has no client configured", async () => {
    const u = await makeUser();
    const token = await makeLink(u.id, "github");

    // Explicitly blank rather than relying on the ambient env: the pool
    // loads `.dev.vars`, so a developer who has configured the connector
    // locally would otherwise see this test redirect to GitHub and fail for
    // a reason that has nothing to do with the code.
    const bare = {
      ...env,
      OAUTH_GITHUB_CLIENT_ID: undefined,
      OAUTH_GITHUB_CLIENT_SECRET: undefined,
    };
    const response = await callWith(`/v1/link/${token}/authorize`, bare as typeof env);
    // A redirect carrying the message, not JSON: a human clicked a button to
    // get here, and a raw error object in the address bar is a dead end.
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toContain("not+set+up+on+this+server");
  });

  it("redirects to GitHub and remembers the state hashed", async () => {
    const u = await makeUser();
    const token = await makeLink(u.id, "github");

    const response = await callWith(`/v1/link/${token}/authorize`, withClient);
    expect(response.status).toBe(302);

    const location = new URL(scalar(response.headers.get("location") ?? undefined, "location"));
    expect(location.host).toBe("github.com");
    expect(location.searchParams.get("client_id")).toBe("Ov23liTEST");
    expect(location.searchParams.get("redirect_uri")).toBe(
      "http://localhost:8787/v1/link/oauth/callback",
    );
    // Least privilege: `repo` would be read *and write* on every repository.
    expect(location.searchParams.get("scope")).toBe("repo read:user");

    const state = scalar(location.searchParams.get("state") ?? undefined, "state");
    const row = scalar(
      (await db().select().from(connectLink).where(eq(connectLink.userId, u.id)))[0],
      "link",
    );
    expect(row.oauthState).toBe(await sha256Base64Url(state));
    expect(row.oauthState).not.toBe(state);
  });

  it("refuses a callback whose state nobody issued", async () => {
    stubGitHub();
    const response = await callWith("/v1/link/oauth/callback?code=abc&state=madeup", withClient);
    expect(response.status).toBe(404);
  });

  it("finishes GitHub at the callback, with no repository to choose", async () => {
    const u = await makeUser();
    const token = await makeLink(u.id, "github");
    stubGitHub();

    const start = await callWith(`/v1/link/${token}/authorize`, withClient);
    const state = new URL(
      scalar(start.headers.get("location") ?? undefined, "location"),
    ).searchParams.get("state");

    const back = await callWith(`/v1/link/oauth/callback?code=abc&state=${state}`, withClient, {
      headers: { cookie: `nm_connect_link=${token}` },
    });
    expect(back.status).toBe(302);
    // No `step=select`: one connection per account, and the repository is a
    // field on each widget rather than a property of the connection.
    expect(back.headers.get("location")).not.toContain("step=select");

    const saved = scalar(
      (await db().select().from(integration).where(eq(integration.userId, u.id)))[0],
      "integration",
    );
    // Named after the account, so it stays right when a tile is repointed.
    expect(saved.label).toBe("GitHub — haxzie");
    expect(saved.accountLabel).toBe("haxzie");
    expect(JSON.stringify(saved)).not.toContain("gho_token");

    const row = scalar(
      (await db().select().from(connectLink).where(eq(connectLink.userId, u.id)))[0],
      "link",
    );
    expect(row.completedAt).toBeTruthy();
    expect(row.pendingCiphertext).toBeNull();
    expect(row.oauthState).toBeNull();
  });

  it("still pauses on a choice for a connector that has one", async () => {
    // Search Console, not GitHub: the selection machinery is live for GA4 and
    // Search Console, and letting its only coverage leave with GitHub's
    // repository picker would retire the tests rather than the code.
    const u = await makeUser();
    const token = await makeLink(u.id, "google-search-console");
    stubGoogle();

    const google = { ...env, GOOGLE_CLIENT_ID: "g.apps", GOOGLE_CLIENT_SECRET: "gsecret" };
    const start = await callWith(`/v1/link/${token}/authorize`, google);
    const state = new URL(
      scalar(start.headers.get("location") ?? undefined, "location"),
    ).searchParams.get("state");

    const back = await callWith(`/v1/link/oauth/callback?code=abc&state=${state}`, google, {
      headers: { cookie: `nm_connect_link=${token}` },
    });
    expect(back.headers.get("location")).toContain("step=select");

    const row = scalar(
      (await db().select().from(connectLink).where(eq(connectLink.userId, u.id)))[0],
      "link",
    );
    // A live credential between two requests, so never in the clear.
    expect(row.pendingCiphertext).toBeTruthy();
    expect(JSON.stringify(row)).not.toContain("ya29.token");

    const options = await callWith(`/v1/link/${token}/options`, google);
    expect(await options.json<{ options: { value: string }[] }>()).toMatchObject({
      options: [{ value: "sc-domain:example.com" }],
    });

    const forged = await callWith(`/v1/link/${token}/select`, google, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ value: "sc-domain:someone-else.com" }),
    });
    // A property name in a POST body is not a claim about what the grant
    // covers, so it is checked against the provider's own list.
    expect(forged.status).toBe(400);

    const done = await callWith(`/v1/link/${token}/select`, google, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ value: "sc-domain:example.com" }),
    });
    expect(await done.json()).toMatchObject({ ok: true });
    expect(done.status).toBe(200);
  });
});
