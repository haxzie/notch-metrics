import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { desktopAuthCode, deviceToken, user } from "@notch/db";
import { eq } from "drizzle-orm";
import worker from "../src/index.ts";
import { randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(deviceToken);
  await db().delete(desktopAuthCode);
  await db().delete(user);
});

const ctx = createExecutionContext();

function post(path: string, body: unknown) {
  return worker.fetch(
    new Request(`http://localhost:8787${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
    env,
    ctx,
  );
}

async function issueCode(userId: string, verifier: string) {
  const code = randomToken(24);
  await db()
    .insert(desktopAuthCode)
    .values({
      code,
      challenge: await sha256Base64Url(verifier),
      userId,
      expiresAt: new Date(Date.now() + 120_000),
    });
  return code;
}

describe("desktop PKCE exchange", () => {
  it("issues a token for the right verifier and stores only its hash", async () => {
    const u = await makeUser();
    const verifier = randomToken(32);
    const code = await issueCode(u.id, verifier);

    const response = await post("/v1/desktop/token", { code, verifier, label: "Studio" });
    expect(response.status).toBe(200);

    const body = await response.json<{ token: string; user: { id: string } }>();
    expect(body.user.id).toBe(u.id);

    const rows = await db().select().from(deviceToken).where(eq(deviceToken.userId, u.id));
    const row = scalar(rows[0], "device token");
    // The bearer token itself exists in the response and the Mac's Keychain and
    // nowhere else, so a D1 dump hands nobody a working session.
    expect(row.tokenHash).toBe(await sha256Base64Url(body.token));
    expect(row.tokenHash).not.toBe(body.token);
  });

  it("rejects the wrong verifier", async () => {
    const u = await makeUser();
    const code = await issueCode(u.id, randomToken(32));
    const response = await post("/v1/desktop/token", {
      code,
      verifier: randomToken(32),
      label: "Studio",
    });
    expect(response.status).toBe(400);
  });

  it("rejects an expired code", async () => {
    const u = await makeUser();
    const verifier = randomToken(32);
    const code = randomToken(24);
    await db()
      .insert(desktopAuthCode)
      .values({
        code,
        challenge: await sha256Base64Url(verifier),
        userId: u.id,
        expiresAt: new Date(Date.now() - 1_000),
      });
    expect((await post("/v1/desktop/token", { code, verifier, label: "x" })).status).toBe(400);
  });

  it("gives the same message for every failure mode", async () => {
    // Distinguishing "unknown code" from "wrong verifier" tells an attacker
    // which half of a guess landed.
    const u = await makeUser();
    const code = await issueCode(u.id, randomToken(32));

    const wrongVerifier = await post("/v1/desktop/token", {
      code,
      verifier: randomToken(32),
      label: "x",
    });
    const unknownCode = await post("/v1/desktop/token", {
      code: randomToken(24),
      verifier: randomToken(32),
      label: "x",
    });

    expect(await wrongVerifier.json()).toEqual(await unknownCode.json());
  });

  it("yields exactly one token when a code is exchanged twice at once", async () => {
    // Consume-then-issue, with the UPDATE conditioned on the row still being
    // unconsumed. The second exchange matches no rows and is refused.
    const u = await makeUser();
    const verifier = randomToken(32);
    const code = await issueCode(u.id, verifier);

    const [a, b] = await Promise.all([
      post("/v1/desktop/token", { code, verifier, label: "one" }),
      post("/v1/desktop/token", { code, verifier, label: "two" }),
    ]);

    expect([a.status, b.status].filter((s) => s === 200)).toHaveLength(1);
    const rows = await db().select().from(deviceToken).where(eq(deviceToken.userId, u.id));
    expect(rows).toHaveLength(1);
  });
});

describe("bearer authentication", () => {
  it("refuses an unknown token", async () => {
    const response = await worker.fetch(
      new Request("http://localhost:8787/v1/me", {
        headers: { authorization: `Bearer ${randomToken(32)}` },
      }),
      env,
      ctx,
    );
    expect(response.status).toBe(401);
  });

  it("refuses a revoked token", async () => {
    const u = await makeUser();
    const verifier = randomToken(32);
    const code = await issueCode(u.id, verifier);
    const { token } = await (
      await post("/v1/desktop/token", { code, verifier, label: "Studio" })
    ).json<{ token: string }>();

    await worker.fetch(
      new Request("http://localhost:8787/v1/desktop/revoke", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
      }),
      env,
      ctx,
    );

    const after = await worker.fetch(
      new Request("http://localhost:8787/v1/me", {
        headers: { authorization: `Bearer ${token}` },
      }),
      env,
      ctx,
    );
    expect(after.status).toBe(401);
  });
});
