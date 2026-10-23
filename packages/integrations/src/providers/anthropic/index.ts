import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import { bucketSum, planWalk } from "../../normalise.ts";
import type {
  AdapterContext,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { metricsFor, provider, type SeriesResult } from "../../metric.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

export { manifest };

export const credentialSchema = z.object({
  admin_key: z.string().min(20),
  workspace_id: z.string().optional(),
});
export type AnthropicCredentials = z.infer<typeof credentialSchema>;

const API = "https://api.anthropic.com/v1";
const HOST = "api.anthropic.com";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/**
 * Midnight UTC at the start of the day `date` falls in.
 *
 * The cost report's `starting_at` is snapped *up* to the next day boundary
 * and its `ending_at` defaults to the start of today, so an unaligned
 * timestamp inside the current day snaps to exactly that default and the
 * request is refused with "ending date must be after starting date" — a 400
 * that reads as a bad key. `now - 24h` is inside the current day for all but
 * the midnight UTC hour, which is why the connector could not be connected
 * at all.
 *
 * The docs say the timestamp is simply snapped, so this is not inferable
 * from them; it was found by walking the boundary against the live API.
 */
function startOfUTCDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/** Buckets one response carries, by `bucket_width`. The cost report is daily only. */
const PER_PAGE = { "1h": 168, "1d": 31 } as const;

/** See the note on OpenAI's: four requests reaches 124 days of daily buckets. */
const MAX_PAGES = 4;

interface CacheCreation {
  ephemeral_1h_input_tokens: number;
  ephemeral_5m_input_tokens: number;
}

interface UsageResult {
  uncached_input_tokens: number;
  cache_read_input_tokens: number;
  cache_creation: CacheCreation | null;
  output_tokens: number;
}

interface CostResult {
  amount: string;
  currency: string;
  workspace_id: string | null;
}

interface Page<R> {
  data: { starting_at: string; ending_at: string; results: R[] }[];
  has_more: boolean;
  next_page: string | null;
}

async function get<T>(ctx: AdapterContext, creds: AnthropicCredentials, url: URL): Promise<T> {
  const response = await ctx.http(url.toString(), {
    headers: {
      "x-api-key": creds.admin_key,
      // Pinned. A future default version could rename a field under an
      // installed app that has no way to be updated for it.
      "anthropic-version": "2023-06-01",
      accept: "application/json",
      // Asked for by the Admin API docs so Anthropic can see integration
      // traffic for what it is.
      "user-agent": "notch-metrics",
    },
  });

  if (response.status === 401 || response.status === 403) {
    // The same 401 covers a bad key, a workspace-scoped key, and an individual
    // account that has no Admin API at all. All three are the user's to fix and
    // none of them is "try again later", so the message has to name all three.
    throw new ProviderError(
      "auth_failed",
      "Claude would not read your usage. This needs an organisation Admin key — workspace keys and individual accounts cannot read the Admin API.",
    );
  }
  if (!response.ok) throw await errorForResponse(HOST, response);
  return response.json<T>();
}

async function walk<R>(
  ctx: AdapterContext,
  creds: AnthropicCredentials,
  path: string,
  params: Record<string, string>,
  repeated: [string, string][] = [],
): Promise<{ at: Date; result: R }[]> {
  const rows: { at: Date; result: R }[] = [];
  let page: string | null = null;

  // Bounded for the same reason as the plan that precedes it: a provider
  // returning fewer buckets per page than documented must not turn four
  // planned requests into a loop that outlives the Worker.
  for (let i = 0; i < MAX_PAGES; i++) {
    const url = new URL(`${API}${path}`);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    for (const [key, value] of repeated) url.searchParams.append(key, value);
    if (page) url.searchParams.set("page", page);

    const body: Page<R> = await get<Page<R>>(ctx, creds, url);
    for (const bucket of body.data) {
      const at = new Date(bucket.starting_at);
      for (const result of bucket.results) rows.push({ at, result });
    }

    if (!body.has_more || !body.next_page) return rows;
    page = body.next_page;
  }

  return rows;
}

function inputTokens(result: UsageResult): number {
  // Four separate fields, and leaving any of them out undercounts silently:
  // a cache-heavy workload reads most of its context rather than sending it,
  // so `uncached_input_tokens` alone can be a tenth of the real volume.
  const creation = result.cache_creation;
  return (
    result.uncached_input_tokens +
    result.cache_read_input_tokens +
    (creation?.ephemeral_5m_input_tokens ?? 0) +
    (creation?.ephemeral_1h_input_tokens ?? 0)
  );
}

async function usage(
  ctx: AdapterContext,
  creds: AnthropicCredentials,
  request: MetricRequest,
  /**
   * Which of the report's columns this metric is.
   *
   * Passed in rather than switched on `request.metric`. The switch had a
   * `default` arm throwing `unsupported` that was unreachable — `fetchMetric`
   * had already decided this was a token metric — and the three cases were
   * the fourth place those three ids were written out.
   */
  pick: (result: UsageResult) => number,
): Promise<SeriesResult> {
  const width = request.granularity === "hour" ? "1h" : "1d";
  const plan = planWalk({
    from: request.from,
    to: request.to,
    comparePrevious: request.comparePrevious,
    bucketMs: width === "1h" ? HOUR_MS : DAY_MS,
    bucketsPerPage: PER_PAGE[width],
    maxPages: MAX_PAGES,
  });

  const rows = await walk<UsageResult>(
    ctx,
    creds,
    "/organizations/usage_report/messages",
    {
      starting_at: plan.start.toISOString(),
      ending_at: request.to.toISOString(),
      bucket_width: width,
      limit: String(PER_PAGE[width]),
    },
    creds.workspace_id ? [["workspace_ids[]", creds.workspace_id]] : [],
  );

  const events = rows.map((row) => ({ at: row.at, amount: pick(row.result) }));
  return series(ctx, events, request, plan.comparePrevious, null);
}

async function spend(
  ctx: AdapterContext,
  creds: AnthropicCredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  if (request.granularity === "hour") {
    throw new ProviderError(
      "unsupported",
      "Claude reports cost once a day. Pick a range of 7 days or longer.",
    );
  }

  const plan = planWalk({
    from: request.from,
    to: request.to,
    comparePrevious: request.comparePrevious,
    bucketMs: DAY_MS,
    bucketsPerPage: PER_PAGE["1d"],
    maxPages: MAX_PAGES,
  });

  // The cost report has no workspace filter, only a grouping. Asking for the
  // grouping and discarding the other rows is the only way to scope it; without
  // the `group_by` every row comes back with `workspace_id: null` and a scoped
  // connection would silently report the whole organisation's bill.
  const scoped = creds.workspace_id !== undefined && creds.workspace_id !== "";
  const rows = await walk<CostResult>(
    ctx,
    creds,
    "/organizations/cost_report",
    {
      // Floored, not passed through: an unaligned start is snapped up to the
      // next midnight, which silently drops the first day of the window.
      starting_at: startOfUTCDay(plan.start).toISOString(),
      ending_at: request.to.toISOString(),
      limit: String(PER_PAGE["1d"]),
    },
    scoped ? [["group_by[]", "workspace_id"]] : [],
  );

  const foreign = new Set<string>();
  const events = rows.flatMap((row) => {
    if (scoped && row.result.workspace_id !== creds.workspace_id) return [];
    const currency = (row.result.currency || "USD").toUpperCase();
    if (currency !== "USD") {
      foreign.add(currency);
      return [];
    }
    // `amount` is a decimal string already in *minor* units — "123.78912" is
    // $1.2379, not $123.79. Reading it as dollars overstates the bill by a
    // hundred times and looks plausible enough to ship.
    const cents = Number(row.result.amount);
    if (!Number.isFinite(cents)) {
      throw new ProviderError("bad_response", `Claude returned "${row.result.amount}" as a cost`);
    }
    return [{ at: row.at, amount: cents }];
  });

  return series(
    ctx,
    events,
    request,
    plan.comparePrevious,
    "USD",
    foreign.size
      ? `${[...foreign].sort().join(" and ")} charges were excluded rather than converted.`
      : undefined,
  );
}

/** Both metric families are flows, so the headline is the window's total. */
function series(
  ctx: AdapterContext,
  events: { at: Date; amount: number }[],
  request: MetricRequest,
  comparePrevious: boolean,
  currency: string | null,
  note?: string,
): SeriesResult {
  const total = (rows: typeof events) => rows.reduce((sum, row) => sum + row.amount, 0);

  const current = events.filter((row) => row.at >= request.from);
  const previous = comparePrevious ? events.filter((row) => row.at < request.from) : [];

  const points = request.wantSeries
    ? bucketSum(current, {
        from: request.from,
        to: request.to,
        granularity: request.granularity,
        timeZone: ctx.timeZone,
      }).map((point) => ({ t: point.t, v: Math.round(point.v) }))
    : [];

  return {
    currency,
    points,
    value: Math.round(total(current)),
    previousValue: comparePrevious ? Math.round(total(previous)) : null,
    ...(note !== undefined ? { note } : {}),
  };
}

const { series: seriesMetric } = metricsFor<AnthropicCredentials>();

/**
 * One of the three token metrics.
 *
 * All three walk the same usage report and differ only in which of its
 * columns they add up — which is the argument, where it used to be a `pick`
 * switch inside `usage`.
 */
function tokenMetric(options: {
  id: MetricId;
  label: string;
  shortLabel: string;
  methodology: string;
  pick: (result: UsageResult) => number;
}) {
  return seriesMetric({
    id: options.id,
    label: options.label,
    shortLabel: options.shortLabel,
    unit: "count",
    // Hourly is real here: the messages report buckets by `1h`. Spend below
    // cannot, which is why the two declare different sets.
    granularities: ["hour", "day", "week"],
    compare: true,
    freshnessSeconds: 300,
    methodology: options.methodology,
    fetch: (ctx, creds, request: MetricRequest) => usage(ctx, creds, request, options.pick),
  });
}

export const tokens = tokenMetric({
  id: "tokens",
  label: "Tokens",
  shortLabel: "Tokens",
  methodology:
    "Input plus output tokens on Messages requests in the window. Input is uncached input, cache reads and cache writes added together, which is what the Usage page shows. It is not what you were billed, since cache reads cost a tenth of the rest.",
  pick: (result) => inputTokens(result) + result.output_tokens,
});

/** `inputTokens` is the helper that sums the cache tiers; hence the suffix. */
export const inputTokensMetric = tokenMetric({
  id: "input_tokens",
  label: "Input tokens",
  shortLabel: "Input",
  methodology:
    "Uncached input, cache reads and both cache-write tiers added together. Each is priced differently; this is the volume, not the bill.",
  pick: inputTokens,
});

export const outputTokens = tokenMetric({
  id: "output_tokens",
  label: "Output tokens",
  shortLabel: "Output",
  methodology:
    "Output tokens generated on Messages requests in the window. Thinking tokens are output tokens and are counted here.",
  pick: (result) => result.output_tokens,
});

export const apiSpend = seriesMetric({
  id: "api_spend",
  label: "API spend",
  shortLabel: "Spend",
  unit: "currency",
  // The cost report is daily-only, same as OpenAI's — so `hour` is absent
  // here where the token metrics above have it, and `24h` is not offered.
  granularities: ["day", "week"],
  compare: true,
  freshnessSeconds: 300,
  methodology:
    "Billed cost per day from the cost report: tokens, web search and code execution. Priority Tier is billed differently and is not included, which is Anthropic's own caveat, not ours.",
  fetch: spend,
});

export const anthropic = provider({
  metrics: [tokens, inputTokensMetric, outputTokens, apiSpend],
  manifest,
  credentialSchema,

  async verify(ctx, creds) {
    const usage = new URL(`${API}/organizations/usage_report/messages`);
    usage.searchParams.set("starting_at", new Date(ctx.now().getTime() - DAY_MS).toISOString());
    usage.searchParams.set("bucket_width", "1d");
    usage.searchParams.set("limit", "1");
    if (creds.workspace_id) usage.searchParams.append("workspace_ids[]", creds.workspace_id);
    await get<Page<UsageResult>>(ctx, creds, usage);

    // Spend is withheld rather than the three token metrics being listed,
    // which is the same narrowing stated the other way up: `provider()`
    // derives what is available from the metrics, so `verify` only has to
    // say what this key cannot reach.
    let spendUnavailable = false;

    // Narrowed rather than fatal, as with OpenAI: token volume is useful on its
    // own, and the two reports are separately available on a scoped key.
    try {
      const costs = new URL(`${API}/organizations/cost_report`);
      // Yesterday 00:00 UTC: the most recent range that is a whole bucket.
      costs.searchParams.set(
        "starting_at",
        new Date(startOfUTCDay(ctx.now()).getTime() - DAY_MS).toISOString(),
      );
      costs.searchParams.set("limit", "1");
      await get<Page<CostResult>>(ctx, creds, costs);
    } catch (error) {
      // A permanent refusal narrows; a transient one is fatal.
      //
      // `availableMetrics` is written once at connect, so letting a 503 pass
      // would hide spend until the user reconnected. But re-throwing
      // everything else meant an optional probe could fail the entire
      // connection — which is what a malformed cost request did, leaving
      // Claude unconnectable even though all three token metrics worked.
      const permanent = new Set(["auth_failed", "bad_response", "unsupported", "not_found"]);
      if (!(error instanceof ProviderError) || !permanent.has(error.code)) throw error;
      spendUnavailable = true;
      ctx.log("anthropic cost report refused, narrowing metrics", {
        code: error.code,
        message: error.message,
      });
    }

    return {
      // The Admin API exposes no organisation name, so a second Claude
      // connection is distinguished by its workspace or, failing that, by the
      // "(2)" `connectionName` appends.
      accountLabel: creds.workspace_id ?? null,
      currency: "USD",
      ...(spendUnavailable ? { unavailableMetrics: ["api_spend" as MetricId] } : {}),
    };
  },
});
