import { and, eq, lt, sql } from "drizzle-orm";
import { getAdapter, manifests } from "@notch/integrations";
import {
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
import { emitConnectionBroken } from "./notifications.ts";
import { callRecorder, recordEvent } from "./events.ts";
import type { RequestTelemetry } from "./telemetry.ts";
import {
  asStale,
  cacheKey,
  type CachedRow,
  freshnessFor,
  granularityFor,
  readCache,
  STALE_FACTOR,
  writeCache,
} from "./metric-cache.ts";

// Re-exported because the cache policy moved out of this file and tests, the
// cron and the routes all still ask this module for it.
export { cacheKey, freshnessFor, WARM_INTERVAL_SECONDS } from "./metric-cache.ts";

/**
 * The breaker's ceiling.
 *
 * `MIN_CALL_SPACING_MS` used to live here too, with an index and a column
 * behind it — and nothing ever read either. Two D1 writes per fetch bought a
 * throttle that did not exist. Spacing between calls to one provider belongs
 * in the HTTP layer where the calls are, not in a row that has to be fetched
 * to be obeyed; `integration.next_allowed_at` is left in the schema, unwritten,
 * because dropping a column is not an additive migration.
 */
const MAX_BREAKER_MS = 6 * 60 * 60 * 1000;

export interface FetchOptions {
  db: Database;
  env: Env;
  userId: string;
  timeZone: string;
  preferredCurrency: string;
  /** Skip the cache entirely. Used by `/refresh`, which is rate-limited hard. */
  force?: boolean;
  /**
   * Somewhere to put a refresh that the caller is not waiting for —
   * `executionCtx.waitUntil` on a request. Absent on the cron, which has no
   * request to hang work off and awaits the refresh instead.
   */
  background?: (work: Promise<unknown>) => void;
  /** Which path is computing, for the cache row's provenance. */
  source?: "request" | "warm";
  /**
   * The request this fetch belongs to, when there is one. Null from the
   * cron, which has no request and no id to attach anything to.
   */
  telemetry?: RequestTelemetry | null;
}

/**
 * Runs `work` over every item, concurrently across keys and sequentially
 * within one, and returns the answers in the order the items came in.
 *
 * Generic so the ordering — the part that goes wrong silently — is testable
 * without a database behind it. Writing each answer at its own index is what
 * makes the result safe whatever order the groups finish in.
 */
export async function runGrouped<Item, Result>(
  items: readonly Item[],
  keyOf: (item: Item) => string,
  work: (item: Item) => Promise<Result>,
): Promise<Result[]> {
  const groups = new Map<string, number[]>();
  items.forEach((item, index) => {
    const group = groups.get(keyOf(item));
    if (group) group.push(index);
    else groups.set(keyOf(item), [index]);
  });

  const results: Result[] = new Array(items.length);
  await Promise.all(
    [...groups.values()].map(async (indices) => {
      for (const index of indices) results[index] = await work(items[index]!);
    }),
  );
  return results;
}

/**
 * Every widget's number, concurrent across integrations and sequential
 * within one.
 *
 * Serialising the whole batch made the notch's first paint the *sum* of
 * every provider's latency — six widgets over four providers was ten
 * seconds of "Loading" on a cold cache, and the ceiling was six times the
 * 20s adapter timeout. Grouping by integration keeps the one thing
 * serialising actually bought: two widgets on the same integration cannot
 * race each other's token refresh, nor hit the provider in the same instant.
 * Across different integrations there is nothing to protect — separate
 * credentials, separate rate limits.
 *
 * The reply stays index-aligned with the request array: the Mac app zips the
 * two together, and a shuffled reply would show every tile another widget's
 * number — a real figure, under the wrong label, with nothing on screen to
 * suggest it.
 */
export async function queryMetrics(
  options: FetchOptions,
  requests: readonly MetricQuery[],
): Promise<MetricResult[]> {
  return runGrouped(
    requests,
    (query) => query.integrationId,
    (query) => queryMetric(options, query),
  );
}

/**
 * Computes in flight, by cache key, so one number is fetched once.
 *
 * A batch asking for the same key twice — two tiles on the same metric and
 * range, which is a normal thing to have — used to be two walks of the same
 * provider list, serialised behind each other. So did a read racing the
 * background refresh it had itself kicked off.
 *
 * Module scope, so the map lives as long as the isolate and no longer. An
 * entry is removed the moment its promise settles; nothing is cached here,
 * only *shared*.
 */
const inFlight = new Map<string, Promise<MetricResult>>();

function share(key: string, work: () => Promise<MetricResult>): Promise<MetricResult> {
  const existing = inFlight.get(key);
  if (existing) return existing;
  const promise = work().finally(() => inFlight.delete(key));
  inFlight.set(key, promise);
  return promise;
}

/**
 * One number, from the cache if there is one at all.
 *
 * The shape of this is the whole performance story, so it is worth being
 * explicit about the three cases:
 *
 *   fresh    — served, no provider call, one D1 read.
 *   expired  — served *immediately* with a refresh started behind it, and
 *              flagged `stale` only once that refresh has had a window to
 *              land and has not.
 *   cold     — computed inline. The only slow path, once per key, ever.
 *
 * It used to be two cases: fresh, or wait for the provider. A tile whose TTL
 * had lapsed by one second paid the same eight seconds as a tile that had
 * never been fetched — with the number it was about to show sitting in the
 * row it had just read. Stale-serving existed, but only as a fallback for a
 * provider that *failed*, which is the rarer half of the problem.
 */
export async function queryMetric(
  options: FetchOptions,
  query: MetricQuery,
): Promise<MetricResult> {
  const { db } = options;
  const granularity = granularityFor(query);
  const key = cacheKey(query, granularity);
  const now = Math.floor(Date.now() / 1000);

  const cached = options.force ? null : await readCache(db, options.userId, key);

  if (cached && cached.expiresAt > now) return cached.payload;

  if (cached?.payload.ok) {
    // The TTL that was actually applied when this row was written, rather
    // than what the manifest says today: reading the integration row to
    // recompute it would put a second D1 round trip on the path whose entire
    // purpose is to answer without one.
    const appliedTtl = Math.max(cached.expiresAt - cached.computedAt, 1);
    // One extra TTL to be refreshed in, then the badge. `stale` means "this is
    // the last value we could fetch" — the notch dims the figure and puts a
    // clock on the tile — so a number that expired ninety seconds ago with a
    // refresh already running behind it must *not* carry it. Past the grace
    // window the refresh has had its chance and the badge is the truth.
    const graceUntil = cached.expiresAt + appliedTtl;
    const servableUntil = cached.expiresAt + appliedTtl * STALE_FACTOR;

    if (now < servableUntil) {
      const refresh = () => share(`${options.userId}:${key}`, () => compute());
      if (!options.background) {
        // No execution context, which means the cron — and for the cron the
        // refresh *is* the work, so it is awaited rather than dropped.
        return refresh();
      }
      options.background(refresh());
      return now < graceUntil ? cached.payload : (asStale(cached.payload) ?? cached.payload);
    }
  }

  return share(`${options.userId}:${key}`, () => compute());

  async function compute(): Promise<MetricResult> {
    return computeMetric(options, query, { granularity, key, cached });
  }
}

/**
 * Goes to the provider, normalises, caches, and records the attempt.
 *
 * Everything slow is in here, and `queryMetric` above decides how often it is
 * reached. Split out so that decision is readable in one screen rather than
 * interleaved with four hundred lines of fetching.
 */
async function computeMetric(
  options: FetchOptions,
  query: MetricQuery,
  context: { granularity: Granularity; key: string; cached: CachedRow | null },
): Promise<MetricResult> {
  const { db } = options;
  const { granularity, key, cached } = context;
  const now = Math.floor(Date.now() / 1000);

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

  const ttlSeconds = freshnessFor(row.provider, query.metric, granularity);

  const staleFallback = (): MetricResult | null => {
    if (!cached) return null;
    if (cached.expiresAt + ttlSeconds * STALE_FACTOR < now) return null;
    return asStale(cached.payload);
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

  const recorder = callRecorder();
  const startedAt = Date.now();

  try {
    const adapter = getAdapter(row.provider);
    // Refreshed first when the connector says the token is about to lapse,
    // so a request inside the lead window does not race the cron.
    //
    // Spanned separately from the fetch because the two fail for unrelated
    // reasons and have unrelated fixes: a slow refresh is our token endpoint
    // round trip, a slow fetch is the provider's data API.
    const { credentials } = options.telemetry
      ? await options.telemetry.span(`credentials.${row.provider}`, () =>
          openFreshCredentials(options.env, db, row),
        )
      : await openFreshCredentials(options.env, db, row);

    const fetchMetric = () =>
      adapter.fetchMetric(
        adapterContext({
          provider: row.provider,
          timeZone: options.timeZone,
          preferredCurrency: options.preferredCurrency,
          signal: AbortSignal.timeout(20_000),
          onCall: recorder.onCall,
        }),
        credentials,
        {
          metric: query.metric,
          granularity,
          from,
          to,
          // Asked for only when the metric can answer it. `true` regardless is
          // what made a 30-day revenue tile fetch sixty days of payments to
          // produce a delta, on metrics whose descriptor says there is no
          // delta to produce.
          comparePrevious: supportsCompare(row.provider, query.metric),
          wantSeries: query.series,
          params: query.params ?? {},
        },
      );

    const raw = options.telemetry
      ? await options.telemetry.span(`provider.${row.provider}.${query.metric}`, fetchMetric)
      : await fetchMetric();

    // The individual provider requests, which `onCall` has been collecting
    // all along. One span each, so a metric that walked six pages looks like
    // six pages rather than one slow call.
    for (const call of recorder.calls) {
      options.telemetry?.record({
        name: `http.${call.host}`,
        ms: call.ms,
        ...(call.status !== null && call.status >= 400 ? { error: String(call.status) } : {}),
      });
    }

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

    await writeCache(db, {
      key,
      userId: options.userId,
      integrationId: row.id,
      result,
      ttlSeconds,
      source: options.source ?? "request",
    });

    await db
      .update(integrationTable)
      .set({
        lastSyncedAt: new Date(),
        failureCount: 0,
        // A success is the only thing that clears the auth strikes. Anything
        // weaker and a connection alternating between a rejection and a
        // timeout would never reach the limit, nor ever be declared healthy.
        authFailures: 0,
        disabledUntil: 0,
        lastErrorCode: null,
        status: "ok",
      })
      .where(eq(integrationTable.id, row.id));

    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "fetch",
      outcome: "ok",
      requestId: options.telemetry?.requestId ?? null,
      metric: query.metric,
      durationMs: Date.now() - startedAt,
      calls: recorder.calls,
      httpStatus: recorder.lastStatus(),
    });

    return result;
  } catch (error) {
    // The integration id in the scope, so a line in the console can be tied
    // to a connection without inferring it from what else happened nearby.
    logError(`metrics.fetch.${row.id}`, error);
    const mapped = toMetricError(error);
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "fetch",
      outcome: "error",
      requestId: options.telemetry?.requestId ?? null,
      metric: query.metric,
      code: mapped.code,
      httpStatus: recorder.lastStatus(),
      durationMs: Date.now() - startedAt,
      calls: recorder.calls,
      detail: error instanceof Error ? error.message : String(error),
    });
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

/** Whether this metric's descriptor says a previous-period figure exists. */
function supportsCompare(provider: string, metric: string): boolean {
  const descriptor = manifests()
    .find((m) => m.id === provider)
    ?.metrics.find((m) => m.id === metric);
  // Unknown descriptors keep the old behaviour: a metric the registry cannot
  // describe is not a metric to start withholding inputs from.
  return descriptor?.supportsCompare ?? true;
}
/**
 * Consecutive `auth_failed` results from the data path before the whole
 * connection is declared broken.
 *
 * Three, to match `REFRESH_STRIKE_LIMIT` — the two paths are answering the
 * same question and a user cannot see which one asked it. Acting on the
 * first rejection is what killed a GitHub connection nine seconds after it
 * was made, on a token that had eight hours left: a 404 for a renamed
 * repository, a spent quota and a WAF all arrive as one rejected request,
 * and none of them means the credential is gone.
 */
export const AUTH_STRIKE_LIMIT = 3;

async function recordFailure(
  env: Env,
  db: Database,
  row: typeof integrationTable.$inferSelect,
  mapped: { code: string; retryAfterSeconds: number | null },
): Promise<void> {
  const failures = row.failureCount + 1;
  const authFailures = mapped.code === "auth_failed" ? row.authFailures + 1 : row.authFailures;
  const broken = mapped.code === "auth_failed" && authFailures >= AUTH_STRIKE_LIMIT;

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
      authFailures,
      disabledUntil: backoffMs > 0 ? Date.now() + backoffMs : 0,
      lastErrorCode: mapped.code,
      lastErrorAt: new Date(),
      status: broken ? "auth_failed" : row.status,
    })
    .where(eq(integrationTable.id, row.id));

  if (broken) {
    await recordEvent(db, {
      userId: row.userId,
      integrationId: row.id,
      kind: "status",
      outcome: "error",
      code: "auth_failed",
      detail: `${authFailures} consecutive rejected requests`,
    });
    // The user's notification first, then ours. The Slack ping is gated on a
    // webhook secret being configured; the user's is not.
    await emitConnectionBroken(db, row.status, row);
    await notifyBroken(env, db, row.status, row);
  }
}

/** Opportunistic, through `waitUntil` — a Worker has no timer of its own. */
export async function sweepCache(db: Database): Promise<void> {
  const cutoff = Math.floor(Date.now() / 1000) - 7 * 24 * 3600;
  await db.delete(metricCache).where(lt(metricCache.expiresAt, cutoff));
}

export const INTERNALS = { STALE_FACTOR, sql };
