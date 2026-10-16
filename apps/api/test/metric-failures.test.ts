import { env } from "cloudflare:test";
import { desc, eq } from "drizzle-orm";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { integration, integrationEvent, metricCache } from "@notch/db";
import { sealCredentials } from "../src/lib/crypto.ts";
import { id } from "../src/lib/ids.ts";
import { AUTH_STRIKE_LIMIT, queryMetric } from "../src/lib/metrics.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(integrationEvent);
  await db().delete(metricCache);
  await db().delete(integration);
});
afterEach(() => vi.unstubAllGlobals());

async function seed() {
  const u = await makeUser();
  const integrationId = id("int");
  const sealed = await sealCredentials(
    env,
    { userId: u.id, integrationId, provider: "github" },
    { access_token: "gho_oldoldoldoldold" },
  );
  await db()
    .insert(integration)
    .values({
      id: integrationId,
      userId: u.id,
      provider: "github",
      label: "GitHub — haxzie",
      credentialCiphertext: sealed.ciphertext,
      credentialIv: sealed.iv,
      credentialWrappedDek: sealed.wrappedDek,
      keyVersion: sealed.keyVersion,
      credentialHint: sealed.hint,
      credentialFingerprint: sealed.fingerprint,
      enabledMetrics: ["stars"],
      availableMetrics: ["stars"],
    });
  return { userId: u.id, integrationId };
}

/** Every GitHub API call answers with this status. */
function stubGitHub(status: number, body: unknown = {}) {
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify(body), { status }));
}

async function row(integrationId: string) {
  return scalar(
    (await db().select().from(integration).where(eq(integration.id, integrationId)))[0],
    "integration",
  );
}

async function fetchStars(userId: string, integrationId: string) {
  return queryMetric(
    { db: db(), env, userId, timeZone: "UTC", preferredCurrency: "USD", force: true },
    {
      integrationId,
      metric: "stars" as never,
      range: "30d",
      series: false,
      params: { repository: "haxzie/genmotion" },
    },
  );
}

describe("what a failed fetch does to the connection", () => {
  /**
   * The production incident, as a test. A repository that was renamed,
   * mistyped or made private answers 404, and that used to mark the whole
   * connection `auth_failed` on the first try — on a token with eight hours
   * left — then lock the row out of the refresh sweep for good.
   */
  it("does not break the connection over a repository it cannot read", async () => {
    const { userId, integrationId } = await seed();
    stubGitHub(404);

    const result = await fetchStars(userId, integrationId);
    expect(result.ok).toBe(false);

    const after = await row(integrationId);
    expect(after.status).toBe("ok");
    expect(after.lastErrorCode).toBe("unsupported");
    expect(after.authFailures).toBe(0);
  });

  it("takes a run of rejections, not one, to declare a connection broken", async () => {
    const { userId, integrationId } = await seed();
    stubGitHub(401);

    for (let attempt = 1; attempt < AUTH_STRIKE_LIMIT; attempt++) {
      await fetchStars(userId, integrationId);
      const mid = await row(integrationId);
      expect(mid.status).toBe("ok");
      expect(mid.authFailures).toBe(attempt);
    }

    await fetchStars(userId, integrationId);
    const after = await row(integrationId);
    expect(after.status).toBe("auth_failed");
    expect(after.authFailures).toBe(AUTH_STRIKE_LIMIT);
    // Never a reauth demand from the data path — only the token endpoint
    // can know the grant itself is gone, and only that excludes the row
    // from refresh.
    expect(after.reauthRequiredAt).toBeNull();
  });

  it("writes an event naming the status that caused the failure", async () => {
    const { userId, integrationId } = await seed();
    stubGitHub(404);
    await fetchStars(userId, integrationId);

    const [event] = await db()
      .select()
      .from(integrationEvent)
      .where(eq(integrationEvent.integrationId, integrationId))
      .orderBy(desc(integrationEvent.at))
      .limit(1);
    const logged = scalar(event, "event");

    expect(logged.kind).toBe("fetch");
    expect(logged.outcome).toBe("error");
    expect(logged.metric).toBe("stars");
    expect(logged.code).toBe("unsupported");
    // The bit that was missing when a connection died and nothing recorded
    // which request did it.
    expect(logged.httpStatus).toBe(404);
    expect(scalar(logged.calls?.[0], "call").host).toBe("api.github.com");
  });
});
