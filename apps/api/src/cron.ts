import { and, eq, inArray, isNotNull, lt, ne, sql } from "drizzle-orm";
import { integration as integrationTable, subscription, user, widget } from "@notch/db";
import type { Env } from "./env.ts";
import { createDb, type Database } from "./lib/db.ts";
import { queryMetric, sweepCache } from "./lib/metrics.ts";
import { sweep as sweepRateLimits } from "./lib/rate-limit.ts";
import { getAdapter } from "@notch/integrations";
import { logError, logInfo } from "./lib/redact.ts";
import { sweepTokenRefresh } from "./lib/token-refresh.ts";
import { sweepEvents } from "./lib/events.ts";
import {
  dueIntegrationIds,
  enabledSubscriptions,
  evaluate,
  evaluateEvents,
  isEventSourced,
  metricFor,
  paramsFor,
  requiredMetrics,
  sweepNotifications,
} from "./lib/notifications.ts";
import { adapterContext } from "./lib/adapter.ts";
import { openFreshCredentials } from "./lib/token-refresh.ts";
import { widgetWarmTargets, type WarmTarget } from "./lib/warm.ts";
import { DEFAULT_GRANULARITY } from "@notch/schemas";

/**
 * Runs every five minutes. Warms caches so the notch opens instantly, and
 * closes the two windows no webhook announces.
 */
export async function scheduled(env: Env): Promise<void> {
  const db = createDb(env);
  // Tokens before metrics, so the poll that follows runs on the new ones
  // rather than on a token with minutes left.
  // The counts, every tick. "Is refresh keeping up" was previously a question
  // you could only answer by querying the database and doing arithmetic on
  // timestamps; as a line per tick it is a graph.
  await sweepTokenRefresh(db, env)
    .then((counts) => logInfo("cron.tokenRefresh", counts))
    .catch((e) => logError("cron.tokenRefresh", e));
  await refreshMetrics(db, env).catch((e) => logError("cron.refresh", e));
  await expireGrace(db).catch((e) => logError("cron.grace", e));
  await sweepNotifications(db).catch((e) => logError("cron.sweepNotifications", e));
  await sweepCache(db).catch((e) => logError("cron.sweepCache", e));
  await sweepEvents(db).catch((e) => logError("cron.sweepEvents", e));
  await sweepRateLimits(db).catch((e) => logError("cron.sweepRateLimits", e));
}

/**
 * A Worker invocation has a wall-clock budget, and a backlog is a far better
 * failure than a timeout that refreshes nothing at all.
 */
const MAX_PER_TICK = 40;
const TICK_SECONDS = 300;

/**
 * Split out of `MAX_PER_TICK` so notification-only integrations cannot crowd
 * widget warming out of a tick.
 *
 * Note that the cap is global rather than per-user, and notifications add
 * demand to it: past this many due integrations the tick falls behind and
 * notification latency degrades. `refreshMetrics` logs when that happens,
 * because the alternative is an invisible regression.
 */
const NOTIFY_BUDGET = 20;

/**
 * Metrics warmed per integration per tick.
 *
 * Four rather than three: a subscription's metric goes first in the ordering,
 * so turning one notification on must not silently stop warming a widget that
 * was already being warmed.
 */
const METRICS_PER_INTEGRATION = 4;

/**
 * The window a notification's metric is warmed over.
 *
 * Subscriptions compare a threshold against the latest value, not against a
 * range somebody picked in the notch, so one window serves them all.
 */
const NOTIFY_RANGE = "30d" as const;

async function refreshMetrics(db: Database, env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000);

  // One query for the whole tick. Every visible tile in the estate is at most
  // a few hundred rows, and asking per integration would be a round trip per
  // connection to learn something a single select already knows.
  const widgetTargets = await widgetWarmTargets(db);

  // Integrations a *visible widget* points at, union those an *enabled
  // subscription* points at. Nobody's notch shows a number they removed, and
  // polling for it spends somebody's Stripe rate limit on nothing — but a
  // notification with no tile behind it still has to be evaluated, or enabling
  // the toggle does nothing, forever, with nothing on screen to say so.
  const ids = await dueIntegrationIds(db, MAX_PER_TICK, NOTIFY_BUDGET);
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

      // Metrics whose arguments live on a widget cannot be warmed from here:
      // this loop knows the connection, not which repository some tile is
      // pointing at. Warming them with no repository would spend a call per
      // tick to produce an error, so they are left to be fetched on demand.
      const descriptors = getAdapter(row.provider).manifest.metrics;
      const widgetScoped = (metric: string) =>
        (descriptors.find((d) => d.id === metric)?.params ?? []).some((f) => f.required);

      const subs = await enabledSubscriptions(db, row.id);

      // Event-sourced notifications first, and in their own catch: they are the
      // only part of this loop that opens credentials for a reason other than a
      // metric, so a provider with a broken event endpoint must not cost the
      // widgets their refresh.
      if (subs.some((sub) => isEventSourced(row.provider, sub))) {
        await evaluateEvents({
          db,
          ctx: adapterContext({
            provider: row.provider,
            timeZone: owner.timezone,
            preferredCurrency: owner.preferredCurrency,
            signal: AbortSignal.timeout(20_000),
          }),
          credentials: (await openFreshCredentials(env, db, row)).credentials,
          row,
          owner,
          subs,
        }).catch((e) => logError(`cron.notify.events.${row.id}`, e));
      }

      // A subscription's own metrics first, so the per-integration cap can
      // never starve a notification of the input it needs. A cold widget just
      // opens a beat slower; a starved notification fails silently.
      //
      // Subscriptions are named by metric and carry their own params, so they
      // are warmed at the default window. Widgets are named by *key* — their
      // own granularity and range — because that is what the notch will read.
      const required = requiredMetrics(row.provider, subs);
      const targets: WarmTarget[] = [
        ...required.map((metric) => ({
          integrationId: row.id,
          metric,
          granularity: DEFAULT_GRANULARITY[NOTIFY_RANGE],
          range: NOTIFY_RANGE,
          params: paramsFor(row.provider, metric, subs),
        })),
        ...(widgetTargets.get(row.id) ?? []).filter(
          (target) =>
            !required.includes(target.metric) &&
            // A subscription carries its own params, so unlike a widget-scoped
            // metric it *is* warmable from here.
            !widgetScoped(target.metric),
        ),
      ];

      for (const target of targets.slice(0, METRICS_PER_INTEGRATION)) {
        const result = await queryMetric(
          {
            db,
            env,
            userId: row.userId,
            timeZone: owner.timezone,
            preferredCurrency: owner.preferredCurrency,
            source: "warm",
            // A notification's own metric is refetched unconditionally; a
            // widget's is not. The difference is what each one is for: an
            // alert is a claim about *now*, and evaluating it against a row a
            // user's poll happened to write four minutes ago adds that long to
            // every alert. A tile is a glance, and a four-minute-old figure is
            // the normal case rather than a defect.
            force: required.includes(target.metric),
          },
          {
            integrationId: row.id,
            metric: target.metric as never,
            granularity: target.granularity,
            range: target.range,
            series: true,
            params: target.params,
          },
        );

        // Evaluated on the series we just fetched: no second provider call, no
        // cache read, no integration read. Its own catch inside the per-row
        // try, for the same reason the loop is awaited-with-per-item-catch — a
        // bad descriptor must not abort the rest of the tick.
        const relevant = subs.filter((s) => metricFor(row.provider, s) === target.metric);
        if (relevant.length > 0) {
          await evaluate({ db, row, owner, subs: relevant, metric: target.metric, result }).catch(
            (e) => logError(`cron.notify.${row.id}`, e),
          );
        }
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
