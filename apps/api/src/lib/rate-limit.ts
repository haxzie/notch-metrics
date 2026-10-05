import { and, eq, lt, sql } from "drizzle-orm";
import { rateLimit } from "@notch/db";
import type { Database } from "./db.ts";

/**
 * Fixed-window rate limiting in D1.
 *
 * The two statements below are the whole implementation and their ordering is
 * load-bearing. `insert … onConflictDoNothing` establishes the row without
 * racing; the conditional `update … where count < limit` is what actually
 * grants the slot, and because SQLite serialises writes, exactly one of two
 * concurrent callers at `count === limit - 1` sees a changed row. Doing the
 * read and the write as separate statements would let both through.
 *
 * This is also why the API's tests run inside workerd against real D1 rather
 * than against a mock: the claim being tested is a claim about SQLite.
 */
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
}

export async function take(
  db: Database,
  subject: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - (now % windowSeconds);

  await db.insert(rateLimit).values({ subject, windowStart, count: 0 }).onConflictDoNothing();

  const updated = await db
    .update(rateLimit)
    .set({ count: sql`${rateLimit.count} + 1` })
    .where(
      and(
        eq(rateLimit.subject, subject),
        eq(rateLimit.windowStart, windowStart),
        lt(rateLimit.count, limit),
      ),
    )
    .returning({ count: rateLimit.count });

  const row = updated[0];
  if (!row) {
    return { allowed: false, remaining: 0, retryAfterSeconds: windowStart + windowSeconds - now };
  }
  return { allowed: true, remaining: limit - row.count, retryAfterSeconds: 0 };
}

/**
 * Drops windows that have closed.
 *
 * Called opportunistically through `waitUntil` rather than on a timer, because
 * a Worker has no timer that outlives a request.
 */
export async function sweep(db: Database, olderThanSeconds = 3600): Promise<void> {
  const cutoff = Math.floor(Date.now() / 1000) - olderThanSeconds;
  await db.delete(rateLimit).where(lt(rateLimit.windowStart, cutoff));
}
