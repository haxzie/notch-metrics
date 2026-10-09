import { and, eq, lt, sql } from "drizzle-orm";
import { getAdapter } from "@notch/integrations";
import {
  DEFAULT_GRANULARITY,
  RANGE_DURATION_MS,
  type Granularity,
  type MetricQuery,
  MetricFormat,
  type MetricResult,
  type MetricSeries,
} from "@notch/schemas";
import { integration as integrationTable, metricCache } from "@notch/db";
import type { Env } from "../env.ts";
import type { Database } from "./db.ts";
import { adapterContext, toMetricError } from "./adapter.ts";
import { openFreshCredentials } from "./token-refresh.ts";
import { percentChange } from "@notch/integrations";
import { logError } from "./redact.ts";
import { notifyBroken } from "./slack.ts";

/**
 * How long a computed envelope stays fresh.
 *
 * Coarser granularities change more slowly, so there is no reason to re-walk
 * Stripe's subscription list every five minutes for a monthly figure.
 */
const TTL_SECONDS: Record<Granularity, number> = {
  hour: 300,
  day: 900,
  week: 3600,
  month: 3600,
};

/**
 * Past its TTL but within this multiple, a row is still served — flagged
 * `stale` — while a refresh runs behind it. Yesterday's MRR greyed out is a
 * better dashboard than a spinner for as long as a provider is down.
 */
const STALE_FACTOR = 4;

export function cacheKey(q: MetricQuery, granularity: Granularity): string {
  const base = `${q.integrationId}:${q.metric}:${granularity}:${q.range}`;

  // Sorted, so two orderings of the same widget are one entry rather than two.
  // Being in the key at all is not a cache-efficiency question: one GitHub
  // connection now serves a tile per repository, so two widgets differing only
  // by `repository` would otherwise share an entry and serve each other's star
  // count — wrong, plausible, and silent.
  const params = Object.entries(q.params ?? {})
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([k, v]) => `${k}=${v}`)
    .join(",");

  // Appended only when there are some, so every widget that predates
  // parameters keeps the exact key it already has. A trailing separator would
  // orphan every cached metric in the estate on the deploy that shipped this,
  // and every notch would go to its provider at once to refill.
  return params ? `${base}:${params}` : base;
}

/** Spacing between outbound calls for one integration, and the breaker's ceiling. */
const MIN_CALL_SPACING_MS = 2_000;
const MAX_BREAKER_MS = 6 * 60 * 60 * 1000;

export interface FetchOptions {
  db: Database;
  env: Env;
  userId: string;
  timeZone: string;
  preferredCurrency: string;
  /** Skip the cache entirely. Used by `/refresh`, which is rate-limited hard. */
  force?: boolean;
}

export async function queryMetric(
  options: FetchOptions,
  query: MetricQuery,
): Promise<MetricResult> {
  const { db } = options;
  const granularity = query.granularity ?? DEFAULT_GRANULARITY[query.range];
  const key = cacheKey(query, granularity);
  const now = Math.floor(Date.now() / 1000);

  const [cached] = await db
    .select()
    .from(metricCache)
    .where(and(eq(metricCache.cacheKey, key), eq(metricCache.userId, options.userId)))
    .limit(1);

  if (cached && !options.force && cached.expiresAt > now) {
    return JSON.parse(cached.payload) as MetricResult;
  }

  const [row] = await db
    .select()
    .from(integrationTable)
    .where(
      and(
        eq(integrationTable.id, query.integrationId),
        eq(integrationTable.userId, options.userId),
      ),
    )
    .limit(1);

  if (!row) {
    return {
      ok: false,
      integrationId: query.integrationId,
      metric: query.metric,
      code: "not_found",
      message: "That integration no longer exists.",
      retryAfterSeconds: null,
    };
  }

  const staleFallback = (): MetricResult | null => {
    if (!cached) return null;
    const payload = JSON.parse(cached.payload) as MetricResult;
    if (!payload.ok) return null;
    if (cached.expiresAt + TTL_SECONDS[granularity] * STALE_FACTOR < now) return null;
    return { ok: true, series: { ...payload.series, stale: true } };
  };

  // A revoked key is not retried. Polling it every five minutes forever is how
  // an account gets its IP blocked, and the user has to reconnect regardless.
  if (row.status === "auth_failed") {
    return (
      staleFallback() ?? {
        ok: false,
        integrationId: row.id,
        metric: query.metric,
        code: "auth_failed",
        message: `Reconnect ${row.label} — that key no longer works.`,
        retryAfterSeconds: null,
      }
    );
  }

  if (row.disabledUntil > Date.now()) {
    return (
      staleFallback() ?? {
        ok: false,
        integrationId: row.id,
        metric: query.metric,
        code: "rate_limited",
        message: `${row.label} is backing off after repeated failures.`,
        retryAfterSeconds: Math.ceil((row.disabledUntil - Date.now()) / 1000),
      }
    );
  }

  const to = new Date();
  const from = new Date(to.getTime() - RANGE_DURATION_MS[query.range]);

  try {
    const adapter = getAdapter(row.provider);
    // Refreshed first when the connector says the token is about to lapse,
    // so a request inside the lead window does not race the cron.
    const { credentials } = await openFreshCredentials(options.env, db, row);

    const raw = await adapter.fetchMetric(
      adapterContext({
        provider: row.provider,
        timeZone: options.timeZone,
        preferredCurrency: options.preferredCurrency,
        signal: AbortSignal.timeout(20_000),
      }),
      credentials,
      {
        metric: query.metric,
        granularity,
        from,
        to,
        comparePrevious: true,
        wantSeries: query.series,
        params: query.params ?? {},
      },
    );

    const series: MetricSeries = {
      integrationId: row.id,
      metric: query.metric,
      unit: raw.unit,
      currency: raw.currency,
      value: raw.value,
      previousValue: raw.previousValue,
      delta:
        raw.previousValue === null
          ? null
          : {
              absolute: raw.value - raw.previousValue,
              percent: percentChange(raw.value, raw.previousValue),
            },
      points: raw.points.map((p) => ({ t: p.t.toISOString(), v: p.v })),
      granularity,
      range: query.range,
      from: from.toISOString(),
      to: to.toISOString(),
      // The adapter's say on rendering, when the unit alone gets it wrong.
      // Filled through the schema so the defaults apply to what it left out.
      format: raw.format ? MetricFormat.parse(raw.format) : null,
      generatedAt: new Date().toISOString(),
      stale: false,
      ...(raw.items
        ? { items: raw.items.map((item) => ({ ...item, t: item.t.toISOString() })) }
        : {}),
    };

    const result: MetricResult = { ok: true, series };
    const expiresAt = now + TTL_SECONDS[granularity];

    await db
      .insert(metricCache)
      .values({
        cacheKey: key,
        userId: options.userId,
        integrationId: row.id,
        payload: JSON.stringify(result),
        etag: `"${now}-${row.id}"`,
        computedAt: now,
        expiresAt,
        source: options.force ? "request" : "request",
      })
      .onConflictDoUpdate({
        target: metricCache.cacheKey,
        set: {
          payload: JSON.stringify(result),
          computedAt: now,
          expiresAt,
          etag: `"${now}-${row.id}"`,
        },
      });

    await db
      .update(integrationTable)
      .set({
        lastSyncedAt: new Date(),
        failureCount: 0,
        disabledUntil: 0,
        lastErrorCode: null,
        status: "ok",
        nextAllowedAt: Date.now() + MIN_CALL_SPACING_MS,
      })
      .where(eq(integrationTable.id, row.id));

    return result;
  } catch (error) {
    logError("metrics.fetch", error);
    const mapped = toMetricError(error);
    await recordFailure(options.env, db, row, mapped);
    return (
      staleFallback() ?? {
        ok: false,
        integrationId: row.id,
        metric: query.metric,
        code: mapped.code,
        message: mapped.message,
        retryAfterSeconds: mapped.retryAfterSeconds,
      }
    );
  }
}

async function recordFailure(
  env: Env,
  db: Database,
  row: typeof integrationTable.$inferSelect,
  mapped: { code: string; retryAfterSeconds: number | null },
): Promise<void> {
  const failures = row.failureCount + 1;

  // A provider that told us exactly how long to wait is obeyed literally.
  // Otherwise: exponential backoff from a minute, capped at six hours, and only
  // after three consecutive failures so one blip does not disable a widget.
  const backoffMs = mapped.retryAfterSeconds
    ? mapped.retryAfterSeconds * 1000
    : failures >= 3
      ? Math.min(2 ** (failures - 3) * 60_000, MAX_BREAKER_MS)
      : 0;

  await db
    .update(integrationTable)
    .set({
      failureCount: failures,
      disabledUntil: backoffMs > 0 ? Date.now() + backoffMs : 0,
      lastErrorCode: mapped.code,
      lastErrorAt: new Date(),
      status: mapped.code === "auth_failed" ? "auth_failed" : row.status,
      nextAllowedAt: Date.now() + MIN_CALL_SPACING_MS,
    })
    .where(eq(integrationTable.id, row.id));

  if (mapped.code === "auth_failed") await notifyBroken(env, db, row.status, row);
}

/** Opportunistic, through `waitUntil` — a Worker has no timer of its own. */
export async function sweepCache(db: Database): Promise<void> {
  const cutoff = Math.floor(Date.now() / 1000) - 7 * 24 * 3600;
  await db.delete(metricCache).where(lt(metricCache.expiresAt, cutoff));
}

export const INTERNALS = { TTL_SECONDS, STALE_FACTOR, sql };
