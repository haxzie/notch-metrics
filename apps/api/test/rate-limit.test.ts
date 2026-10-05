import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { rateLimit } from "@notch/db";
import { take } from "../src/lib/rate-limit.ts";
import { db, migrate } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(rateLimit);
});

describe("fixed-window rate limiting", () => {
  it("allows up to the limit and then refuses", async () => {
    for (let i = 0; i < 3; i++) {
      expect((await take(db(), "user:a", 3, 60)).allowed).toBe(true);
    }
    const denied = await take(db(), "user:a", 3, 60);
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("grants exactly one slot to two concurrent callers at the boundary", async () => {
    // The reason this suite runs in workerd against real D1. The grant is a
    // single conditional UPDATE, and the claim being tested is that SQLite
    // serialises the two writes. A read-then-write would let both through, and
    // a mock would happily agree with either implementation.
    await take(db(), "user:b", 2, 60);
    const [first, second] = await Promise.all([
      take(db(), "user:b", 2, 60),
      take(db(), "user:b", 2, 60),
    ]);
    expect([first.allowed, second.allowed].filter(Boolean)).toHaveLength(1);
  });

  it("keeps subjects independent", async () => {
    await take(db(), "user:c", 1, 60);
    expect((await take(db(), "user:c", 1, 60)).allowed).toBe(false);
    expect((await take(db(), "user:d", 1, 60)).allowed).toBe(true);
  });
});
