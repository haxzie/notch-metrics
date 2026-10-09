import { and, eq, inArray, isNotNull, lt, ne, sql } from "drizzle-orm";
import { integration as integrationTable, subscription, user, widget } from "@notch/db";
import type { Env } from "./env.ts";
import { createDb, type Database } from "./lib/db.ts";
import { queryMetric, sweepCache } from "./lib/metrics.ts";
import { sweep as sweepRateLimits } from "./lib/rate-limit.ts";
import { logError } from "./lib/redact.ts";
import { sweepTokenRefresh } from "./lib/token-refresh.ts";

/**
 * Runs every five minutes. Warms caches so the notch opens instantly, and
 * closes the two windows no webhook announces.
 */
export async function scheduled(env: Env): Promise<void> {
  const db = createDb(env);
  // Tokens before metrics, so the poll that follows runs on the new ones
  // rather than on a token with minutes left.
  await sweepTokenRefresh(db, env).catch((e) => logError("cron.tokenRefresh", e));
  await refreshMetrics(db, env).catch((e) => logError("cron.refresh", e));
  await expireGrace(db).catch((e) => logError("cron.grace", e));
  await sweepCache(db).catch((e) => logError("cron.sweepCache", e));
  await sweepRateLimits(db).catch((e) => logError("cron.sweepRateLimits", e));
}

/**
 * A Worker invocation has a wall-clock budget, and a backlog is a far better
 * failure than a timeout that refreshes nothing at all.
 */
const MAX_PER_TICK = 40;
const TICK_SECONDS = 300;

async function refreshMetrics(db: Database, env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000);

  // Only integrations a *visible widget* actually points at. Nobody's notch
  // shows a number they removed, and polling for it spends somebody's Stripe
  // rate limit on nothing.
  const referenced = await db
    .selectDistinct({ integrationId: widget.integrationId })
    .from(widget)
    .where(and(eq(widget.visible, true), isNotNull(widget.integrationId)));

  const ids = referenced.map((r) => r.integrationId).filter((v): v is string => v !== null);
  if (ids.length === 0) return;

  const due = await db
    .select()
    .from(integrationTable)
    .where(
      and(
        inArray(integrationTable.id, ids),
        // A revoked key is never retried here either.
        ne(integrationTable.status, "auth_failed"),
        lt(integrationTable.disabledUntil, Date.now()),
        // The stagger. Each integration carries a random offset in 0..299, so
        // a tick picks up roughly a fifth of them rather than trying the whole
        // account at once and arriving at Stripe as one burst from one IP.
        sql`((${now} - ${integrationTable.refreshOffsetSeconds}) % ${TICK_SECONDS}) < 60`,
      ),
    )
    .orderBy(integrationTable.lastSyncedAt)
    .limit(MAX_PER_TICK);

  for (const row of due) {
    // Awaited with a per-item catch rather than Promise.all: one failing
    // provider must not abort the rest of the tick, and the failure needs to
    // be attributable to the integration that caused it.
    try {
      const [owner] = await db.select().from(user).where(eq(user.id, row.userId)).limit(1);
      if (!owner) continue;

      const metrics = row.enabledMetrics ?? [];
      for (const metric of metrics.slice(0, 3)) {
        await queryMetric(
          {
            db,
            env,
            userId: row.userId,
            timeZone: owner.timezone,
            preferredCurrency: owner.preferredCurrency,
            force: true,
          },
          { integrationId: row.id, metric: metric as never, range: "30d", series: true },
        );
      }
    } catch (error) {
      logError(`cron.refresh.${row.id}`, error);
    }
  }
}

/** The grace window closing after a failed renewal. No webhook announces this. */
async function expireGrace(db: Database): Promise<void> {
  const now = new Date();
  const expired = await db
    .select({ userId: subscription.userId })
    .from(subscription)
    .where(and(eq(subscription.status, "past_due"), lt(subscription.graceUntil, now)));

  for (const row of expired) {
    await db
      .update(subscription)
      .set({ status: "expired", graceUntil: null, updatedAt: now })
      .where(eq(subscription.userId, row.userId));
    await db.update(user).set({ plan: "expired" }).where(eq(user.id, row.userId));
  }
}
