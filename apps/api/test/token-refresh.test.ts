import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { integration } from "@notch/db";
import { eq } from "drizzle-orm";
import { openCredentials, sealCredentials, sealedFromRow } from "../src/lib/crypto.ts";
import { id } from "../src/lib/ids.ts";
import {
  openFreshCredentials,
  REFRESH_STRIKE_LIMIT,
  sweepTokenRefresh,
} from "../src/lib/token-refresh.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(integration);
  // The sweep reads the connector's client from the Worker secrets. The test
  // bindings carry none, so these stand in.
  Object.assign(env, { OAUTH_GITHUB_CLIENT_ID: "Iv1.test", OAUTH_GITHUB_CLIENT_SECRET: "s" });
});
afterEach(() => vi.unstubAllGlobals());

const HOUR = 60 * 60 * 1000;

/** A GitHub connection whose token expires `expiresInMs` from now. */
async function seedGitHub(options: {
  expiresInMs: number | null;
  refreshToken?: string;
  lastAttemptAgoMs?: number;
  refreshFailures?: number;
}) {
  const u = await makeUser();
  const integrationId = id("int");
  const credentials: Record<string, string> = {
    access_token: "gho_oldoldoldoldold",
    repository: "haxzie/genmotion",
    ...(options.refreshToken ? { refresh_token: options.refreshToken } : {}),
    ...(options.expiresInMs === null
      ? {}
      : { expires_at: String(Date.now() + options.expiresInMs) }),
  };
  const sealed = await sealCredentials(
    env,
    { userId: u.id, integrationId, provider: "github" },
    credentials,
  );
  await db()
    .insert(integration)
    .values({
      id: integrationId,
      userId: u.id,
      provider: "github",
      label: "GitHub — haxzie/genmotion",
      credentialCiphertext: sealed.ciphertext,
      credentialIv: sealed.iv,
      credentialWrappedDek: sealed.wrappedDek,
      keyVersion: sealed.keyVersion,
      credentialHint: sealed.hint,
      credentialFingerprint: sealed.fingerprint,
      enabledMetrics: ["stars"],
      availableMetrics: ["stars"],
      tokenExpiresAt:
        options.expiresInMs === null ? null : new Date(Date.now() + options.expiresInMs),
      lastRefreshAttemptAt:
        options.lastAttemptAgoMs === undefined
          ? null
          : new Date(Date.now() - options.lastAttemptAgoMs),
      refreshFailures: options.refreshFailures ?? 0,
    });
  return { userId: u.id, integrationId };
}

async function row(integrationId: string) {
  return scalar(
    (await db().select().from(integration).where(eq(integration.id, integrationId)))[0],
    "integration",
  );
}

function stubGitHubToken(body: Record<string, unknown>, status = 200) {
  const calls: string[] = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    calls.push(String(input instanceof Request ? input.url : input));
    return new Response(JSON.stringify(body), { status });
  });
  return calls;
}

/**
 * GitHub's actual contract, which the plain stub above cannot express: a
 * refresh token works exactly once, and the second presentation of it is
 * answered `bad_refresh_token` — indistinguishable from a revoked grant.
 */
function stubRotatingGitHubToken() {
  const spent = new Set<string>();
  const presented: string[] = [];
  let issued = 0;
  vi.stubGlobal("fetch", async (_input: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as { refresh_token?: string };
    const token = body.refresh_token ?? "";
    presented.push(token);
    if (spent.has(token)) {
      // 200 with an error body, as GitHub actually answers.
      return new Response(JSON.stringify({ error: "bad_refresh_token" }), { status: 200 });
    }
    spent.add(token);
    issued += 1;
    return new Response(
      JSON.stringify({
        access_token: `gho_rotated${issued}`,
        refresh_token: `ghr_rotated${issued}`,
        expires_in: 28800,
      }),
      { status: 200 },
    );
  });
  return presented;
}

/**
 * The race that logged GitHub out roughly every sixth refresh.
 *
 * Two callers — a woken Mac's overlapping metric batches, or one of those
 * and the cron — both found the token due and both posted the same
 * single-use refresh token. The loser was told `bad_refresh_token` about a
 * grant the winner had just proved alive, and marked the connection as
 * needing reauthorisation. Nothing in the connector could see it: the race
 * is between two callers of `openFreshCredentials`, and every provider whose
 * refresh token survives being used is immune.
 */
describe("concurrent refresh of one row", () => {
  it("posts the refresh token once and keeps the connection", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_first",
    });
    const presented = stubRotatingGitHubToken();
    const snapshot = await row(integrationId);

    const [a, b] = await Promise.all([
      openFreshCredentials(env, db(), snapshot),
      openFreshCredentials(env, db(), snapshot),
    ]);

    // One claim, one call. The second caller never reaches the endpoint.
    expect(presented).toEqual(["ghr_first"]);
    expect([a.refreshed, b.refreshed].filter(Boolean)).toHaveLength(1);

    const after = await row(integrationId);
    expect(after.status).toBe("ok");
    expect(after.reauthRequiredAt).toBeNull();
    expect(after.lastErrorCode).toBeNull();

    const stored = await openCredentials(
      env,
      { userId: after.userId, integrationId, provider: "github" },
      sealedFromRow(after),
    );
    expect(stored.access_token).toBe("gho_rotated1");
    expect(stored.refresh_token).toBe("ghr_rotated1");
  });

  it("treats a spent refresh token as a lost race, not a dead grant", async () => {
    // The claim is a lease, not a proof: a second isolate can have read the
    // row before the claim landed, and a D1 hiccup can lose one outright. So
    // the fatal branch has to survive being reached anyway.
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_first",
    });
    const presented = stubRotatingGitHubToken();
    const stale = await row(integrationId);

    await openFreshCredentials(env, db(), stale);
    // Free the lease, then come back holding the pre-rotation row.
    await db()
      .update(integration)
      .set({ lastRefreshAttemptAt: new Date(Date.now() - 10 * 60 * 1000) })
      .where(eq(integration.id, integrationId));

    const second = await openFreshCredentials(env, db(), stale);

    expect(presented).toEqual(["ghr_first", "ghr_first"]);
    // The winner's credentials, not the stale ones we arrived with.
    expect(second.credentials.access_token).toBe("gho_rotated1");

    const after = await row(integrationId);
    expect(after.status).toBe("ok");
    expect(after.reauthRequiredAt).toBeNull();
    expect(after.lastErrorCode).toBeNull();
  });

  /**
   * The mark the race left behind. The production GitHub row sat for three
   * days reading `status: ok` with a reauth demand still on it, which the
   * sweep excludes on — so the cron never pre-warmed it again and it lived
   * on whichever request happened to find the token due.
   */
  it("lifts a stale reauth demand once a refresh succeeds, and returns to the sweep", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_stillgood",
    });
    await db()
      .update(integration)
      .set({ reauthRequiredAt: new Date() })
      .where(eq(integration.id, integrationId));
    stubRotatingGitHubToken();

    // The fetch path, which has no business refusing to refresh a row the
    // sweep has written off.
    const { refreshed } = await openFreshCredentials(env, db(), await row(integrationId));
    expect(refreshed).toBe(true);
    expect((await row(integrationId)).reauthRequiredAt).toBeNull();
  });

  it("still marks a genuinely dead grant when nothing else rotated it", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_dead",
    });
    stubGitHubToken({ error: "bad_refresh_token" });

    await openFreshCredentials(env, db(), await row(integrationId));

    const after = await row(integrationId);
    expect(after.status).toBe("auth_failed");
    expect(after.reauthRequiredAt).not.toBeNull();
  });
});

describe("token refresh sweep", () => {
  it("rotates a token inside the lead window and re-seals the blob", async () => {
    const { userId, integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_firstfirstfirst",
    });
    const before = await row(integrationId);
    const calls = stubGitHubToken({
      access_token: "gho_newnewnewnewnew",
      refresh_token: "ghr_secondsecond",
      expires_in: 28800,
    });

    const result = await sweepTokenRefresh(db(), env);

    expect(result).toEqual({ candidates: 1, refreshed: 1, failed: 0 });
    expect(calls).toEqual(["https://github.com/login/oauth/access_token"]);

    const after = await row(integrationId);
    expect(after.credentialCiphertext).not.toBe(before.credentialCiphertext);
    expect(after.tokenExpiresAt!.getTime()).toBeGreaterThan(Date.now() + 7 * HOUR);
    expect(after.lastRefreshAttemptAt).not.toBeNull();
    expect(after.refreshFailures).toBe(0);
    expect(after.status).toBe("ok");

    // The new blob decrypts under the same scope and holds the new pair plus
    // the repository the user chose.
    const opened = await openCredentials(
      env,
      { userId, integrationId, provider: "github" },
      sealedFromRow(after),
    );
    expect(opened).toMatchObject({
      access_token: "gho_newnewnewnewnew",
      refresh_token: "ghr_secondsecond",
      repository: "haxzie/genmotion",
    });
  });

  it("leaves a token alone while it has more than the lead time left", async () => {
    await seedGitHub({ expiresInMs: 7 * HOUR, refreshToken: "ghr_x" });
    const calls = stubGitHubToken({ access_token: "never" });
    const result = await sweepTokenRefresh(db(), env);
    expect(result.candidates).toBe(0);
    expect(calls).toHaveLength(0);
  });

  it("honours the floor between attempts", async () => {
    await seedGitHub({
      expiresInMs: 10 * 60 * 1000,
      refreshToken: "ghr_x",
      lastAttemptAgoMs: 60_000,
    });
    const calls = stubGitHubToken({ access_token: "never" });
    expect((await sweepTokenRefresh(db(), env)).candidates).toBe(0);
    expect(calls).toHaveLength(0);
  });

  it("checks a row with unknown expiry once and records the attempt", async () => {
    // The row this is for: a connection made before expiry was stored, with a
    // token that never expires. Nothing to rotate, nothing to ask again
    // before the floor.
    const { integrationId } = await seedGitHub({ expiresInMs: null });
    const calls = stubGitHubToken({ access_token: "never" });
    expect(await sweepTokenRefresh(db(), env)).toEqual({ candidates: 1, refreshed: 0, failed: 0 });
    expect(calls).toHaveLength(0);
    const after = await row(integrationId);
    expect(after.lastRefreshAttemptAt).not.toBeNull();
    expect(after.status).toBe("ok");
    expect((await sweepTokenRefresh(db(), env)).candidates).toBe(0);
  });

  it("marks a dead grant as needing reconnection at once", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 10 * 60 * 1000,
      refreshToken: "ghr_dead",
    });
    stubGitHubToken({ error: "bad_refresh_token" });
    await sweepTokenRefresh(db(), env);
    const after = await row(integrationId);
    expect(after.status).toBe("auth_failed");
    expect(after.lastErrorCode).toBe("auth_failed");
  });

  it("counts a provider blip as a strike, not a reconnect", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 10 * 60 * 1000,
      refreshToken: "ghr_x",
    });
    stubGitHubToken({}, 502);
    await sweepTokenRefresh(db(), env);
    const after = await row(integrationId);
    expect(after.status).toBe("ok");
    expect(after.refreshFailures).toBe(1);
    expect(after.lastRefreshAttemptAt).not.toBeNull();
  });

  it("gives up only after the strike limit with the token actually expired", async () => {
    const stillValid = await seedGitHub({
      expiresInMs: 10 * 60 * 1000,
      refreshToken: "ghr_x",
      refreshFailures: REFRESH_STRIKE_LIMIT - 1,
    });
    const expired = await seedGitHub({
      expiresInMs: -1000,
      refreshToken: "ghr_y",
      refreshFailures: REFRESH_STRIKE_LIMIT - 1,
    });
    stubGitHubToken({}, 502);
    await sweepTokenRefresh(db(), env);
    expect((await row(stillValid.integrationId)).status).toBe("ok");
    expect((await row(expired.integrationId)).status).toBe("auth_failed");
  });

  it("skips a connection whose grant is actually gone", async () => {
    const { integrationId } = await seedGitHub({ expiresInMs: -1000, refreshToken: "ghr_x" });
    await db()
      .update(integration)
      .set({ status: "auth_failed", reauthRequiredAt: new Date() })
      .where(eq(integration.id, integrationId));
    const calls = stubGitHubToken({ access_token: "never" });
    expect((await sweepTokenRefresh(db(), env)).candidates).toBe(0);
    expect(calls).toHaveLength(0);
  });

  /**
   * The regression that cost a production connection. A rejected *data*
   * request marked the row `auth_failed`, the sweep excluded every such row,
   * and the refresh token — still perfectly good — was never used again. The
   * token lapsed hours later and the refresh machinery looked broken when it
   * had simply never been asked.
   */
  it("still refreshes a row marked auth_failed that was never told to reauthorise", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_stillgood",
    });
    await db()
      .update(integration)
      .set({ status: "auth_failed", lastErrorCode: "auth_failed", authFailures: 3 })
      .where(eq(integration.id, integrationId));
    const calls = stubGitHubToken({
      access_token: "gho_newnewnewnewnew",
      refresh_token: "ghr_rotated",
      expires_in: 28800,
    });

    expect(await sweepTokenRefresh(db(), env)).toEqual({
      candidates: 1,
      refreshed: 1,
      failed: 0,
    });
    expect(calls).toHaveLength(1);

    // And a refresh that succeeded proves the grant is alive, so the
    // connection comes back on its own rather than waiting for a human.
    const after = await row(integrationId);
    expect(after.status).toBe("ok");
    expect(after.lastErrorCode).toBeNull();
    expect(after.authFailures).toBe(0);
  });

  it("records a reauth demand so the row is excluded from then on", async () => {
    const { integrationId } = await seedGitHub({
      expiresInMs: 30 * 60 * 1000,
      refreshToken: "ghr_dead",
    });
    stubGitHubToken({ error: "bad_refresh_token" });

    await sweepTokenRefresh(db(), env);
    const after = await row(integrationId);
    expect(after.status).toBe("auth_failed");
    expect(after.reauthRequiredAt).not.toBeNull();

    // Second sweep: nothing left to try.
    const calls = stubGitHubToken({ access_token: "never" });
    expect((await sweepTokenRefresh(db(), env)).candidates).toBe(0);
    expect(calls).toHaveLength(0);
  });
});
