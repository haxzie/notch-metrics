import { env } from "cloudflare:test";
import { asc, eq } from "drizzle-orm";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { integration, integrationEvent } from "@notch/db";
import { sealCredentials } from "../src/lib/crypto.ts";
import { INTERNALS, recordEvent, sweepEvents } from "../src/lib/events.ts";
import { id } from "../src/lib/ids.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(integrationEvent);
  await db().delete(integration);
});

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

async function events(integrationId: string) {
  return db()
    .select()
    .from(integrationEvent)
    .where(eq(integrationEvent.integrationId, integrationId))
    .orderBy(asc(integrationEvent.at));
}

describe("the integration event log", () => {
  it("keeps the provider calls an attempt made", async () => {
    const { userId, integrationId } = await seed();
    await recordEvent(db(), {
      userId,
      integrationId,
      kind: "fetch",
      outcome: "error",
      metric: "stars",
      code: "unsupported",
      httpStatus: 404,
      calls: [{ host: "api.github.com", method: "GET", status: 404, ms: 83 }],
    });

    const [row] = await events(integrationId);
    const event = scalar(row, "event");
    expect(event.code).toBe("unsupported");
    expect(event.httpStatus).toBe(404);
    expect(event.calls).toEqual([{ host: "api.github.com", method: "GET", status: 404, ms: 83 }]);
  });

  /**
   * The whole point of the table is to be readable a week later by somebody
   * who was not there. A row that quoted a token would make it unreadable
   * by anybody who should not see one, so the redaction runs here too and
   * not only at the console boundary.
   */
  it("redacts a credential that reached an error message", async () => {
    const { userId, integrationId } = await seed();
    await recordEvent(db(), {
      userId,
      integrationId,
      kind: "fetch",
      outcome: "error",
      detail: "GET /repos failed with Bearer gho_abcdefghijklmnopqrst",
    });

    const event = scalar((await events(integrationId))[0], "event");
    expect(event.detail).not.toContain("gho_abcdefghijklmnopqrst");
    expect(event.detail).toContain("[redacted]");
  });

  it("bounds the detail and the call list", async () => {
    const { userId, integrationId } = await seed();
    await recordEvent(db(), {
      userId,
      integrationId,
      kind: "fetch",
      outcome: "error",
      detail: "x".repeat(5_000),
      calls: Array.from({ length: 40 }, (_, i) => ({
        host: "api.github.com",
        method: "GET",
        status: 200,
        ms: i,
      })),
    });

    const event = scalar((await events(integrationId))[0], "event");
    expect(event.detail).toHaveLength(INTERNALS.MAX_DETAIL);
    expect(event.calls).toHaveLength(INTERNALS.MAX_CALLS);
    // The *last* calls are kept: an adapter throws on the response it could
    // not use, so the tail is the half that explains the failure.
    expect(scalar(event.calls?.[INTERNALS.MAX_CALLS - 1], "call").ms).toBe(39);
  });

  /**
   * This is the thing that watches everything else. A bug in it must not be
   * able to turn a working metric fetch into a failed one — a lost log line
   * is a worse diagnosis later, a thrown one is a blank widget now.
   */
  it("never throws, even when the write cannot succeed", async () => {
    const { userId } = await seed();
    await expect(
      recordEvent(db(), {
        userId,
        // No such integration, so the foreign key refuses the row.
        integrationId: "int_doesnotexist",
        kind: "fetch",
        outcome: "ok",
      }),
    ).resolves.toBeUndefined();
  });

  it("sweeps rows past the retention window and keeps the rest", async () => {
    const { userId, integrationId } = await seed();
    await recordEvent(db(), { userId, integrationId, kind: "fetch", outcome: "ok" });
    const old = scalar((await events(integrationId))[0], "event");
    // Backdate a copy rather than wait a week.
    await db()
      .insert(integrationEvent)
      .values({
        ...old,
        id: id("ev"),
        at: Math.floor(Date.now() / 1000) - INTERNALS.RETENTION_SECONDS - 60,
      });
    expect(await events(integrationId)).toHaveLength(2);

    await sweepEvents(db());
    expect(await events(integrationId)).toHaveLength(1);
  });
});
