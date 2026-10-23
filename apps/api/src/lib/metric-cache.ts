import { and, eq } from "drizzle-orm";
import { manifests } from "@notch/integrations";
import { metricCache } from "@notch/db";
import {
  DEFAULT_GRANULARITY,
  type Granularity,
  type MetricQuery,
  type MetricResult,
} from "@notch/schemas";
import type { Database } from "./db.ts";

/**
 * Everything that decides *when* a number is re-fetched, in one file.
 *
 * It used to be three: a TTL table here, a manifest field there, and a cron
 * that warmed a different key than the one the app reads. Three answers to one
 * question is how a cache ends up costing provider calls without ever
 * serving a hit — see `freshnessFor` for the specific way that happened.
 */

/**
 * How often the cron comes round. The cache's floor, not just a schedule.
 *
 * A TTL shorter than this cannot produce a hit: the row expires before the
 * next tick can rewrite it, so every read goes to the provider and the
 * warming is pure cost. Dodo's money metrics asked for 60s against a 300s
 * tick, which is exactly that — a tile that was never once served from cache
 * while three `/payments` walks ran every five minutes on its behalf.
 */
export const WARM_INTERVAL_SECONDS = 300;

/**
 * The default by bucket. Coarser granularities move more slowly, so there is
 * no reason to re-walk Stripe's subscription list every five minutes for a
 * monthly figure.
 */
const TTL_SECONDS: Record<Granularity, number> = {
  hour: 300,
  day: 900,
  week: 3600,
  month: 3600,
};

/**
 * Past its TTL but within this multiple, a row is still *served* — flagged
 * `stale` — while a refresh runs behind it. Yesterday's MRR greyed out is a
 * better dashboard than a spinner for as long as a provider is down.
 */
export const STALE_FACTOR = 4;

/**
 * How long this metric's envelope stays fresh.
 *
 * The bucket decides by default and a metric may overrule it, because the
 * connector knows how fast its own data moves: a CI list arrives in a daily
 * bucket like everything else, and holding it for the daily fifteen minutes
 * means a tile reporting a build that has since gone red.
 *
 * Clamped to the warm interval, which is the part that was missing. A
 * descriptor asking for less than one tick is asking for a cache that never
 * hits, and the clamp is here rather than in the manifests so a connector
 * author cannot reintroduce it one provider at a time.
 */
export function freshnessFor(provider: string, metric: string, granularity: Granularity): number {
  // `getAdapter` throws for a provider that is no longer in the registry, and
  // a row can name one. That case has an answer further up — an error result,
  // not a 500 — so it must not be turned into one here.
  const descriptor = manifests()
    .find((m) => m.id === provider)
    ?.metrics.find((m) => m.id === metric);
  const wanted = descriptor?.freshnessSeconds ?? TTL_SECONDS[granularity];
  return Math.max(wanted, WARM_INTERVAL_SECONDS);
}

export function granularityFor(query: MetricQuery): Granularity {
  return query.granularity ?? DEFAULT_GRANULARITY[query.range];
}

/**
 * The identity of a number.
 *
 * Whatever writes a row and whatever reads one must agree on this exactly,
 * which is why the cron now derives its targets from the widgets rather than
 * warming a fixed `30d`: a key that differs by range is a different number,
 * and warming the wrong one is indistinguishable from not warming at all.
 */
export interface KeyParts {
  integrationId: string;
  metric: string;
  range: string;
  params?: Record<string, string> | undefined;
}

export function cacheKey(q: KeyParts, granularity: Granularity): string {
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

export interface CachedRow {
  payload: MetricResult;
  computedAt: number;
  expiresAt: number;
}

export async function readCache(
  db: Database,
  userId: string,
  key: string,
): Promise<CachedRow | null> {
  const [row] = await db
    .select()
    .from(metricCache)
    .where(and(eq(metricCache.cacheKey, key), eq(metricCache.userId, userId)))
    .limit(1);
  if (!row) return null;
  return {
    payload: JSON.parse(row.payload) as MetricResult,
    computedAt: row.computedAt,
    expiresAt: row.expiresAt,
  };
}

export async function writeCache(
  db: Database,
  input: {
    key: string;
    userId: string;
    integrationId: string;
    result: MetricResult;
    ttlSeconds: number;
    /** Which path computed it: a request on the hot path, or the cron. */
    source: "request" | "warm";
  },
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const payload = JSON.stringify(input.result);
  const etag = `"${now}-${input.integrationId}"`;
  const expiresAt = now + input.ttlSeconds;

  await db
    .insert(metricCache)
    .values({
      cacheKey: input.key,
      userId: input.userId,
      integrationId: input.integrationId,
      payload,
      etag,
      computedAt: now,
      expiresAt,
      source: input.source,
    })
    .onConflictDoUpdate({
      target: metricCache.cacheKey,
      set: { payload, computedAt: now, expiresAt, etag, source: input.source },
    });
}

/** Serves a cached envelope as stale: same numbers, flagged for the tile. */
export function asStale(payload: MetricResult): MetricResult | null {
  if (!payload.ok) return null;
  return { ok: true, series: { ...payload.series, stale: true } };
}
