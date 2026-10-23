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
  project_id: z.string().optional(),
});
export type OpenAICredentials = z.infer<typeof credentialSchema>;

const API = "https://api.openai.com/v1";
const HOST = "api.openai.com";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** Buckets OpenAI returns in one response, by `bucket_width`. */
const PER_PAGE = { "1h": 168, "1d": 31 } as const;

/**
 * Four requests per window, which reaches 124 days of daily buckets.
 *
 * Enough for every range up to 90 days; a year is refused by `planWalk` with a
 * message rather than by the Worker's CPU limit with a spinner.
 */
const MAX_PAGES = 4;

interface UsageResult {
  input_tokens: number;
  output_tokens: number;
  num_model_requests: number;
}

interface CostResult {
  amount: { value: number; currency: string } | null;
  organization_id?: string | null;
}

interface Page<R> {
  data: { start_time: number; end_time: number; results: R[] }[];
  has_more: boolean;
  next_page: string | null;
}

async function get<T>(ctx: AdapterContext, creds: OpenAICredentials, url: URL): Promise<T> {
  const response = await ctx.http(url.toString(), {
    headers: {
      authorization: `Bearer ${creds.admin_key}`,
      accept: "application/json",
    },
  });

  if (response.status === 401 || response.status === 403) {
    // Deliberately not the generic "rejected the credentials". The single most
    // common cause is a perfectly valid project key, and telling somebody their
    // key is wrong sends them to regenerate the same kind again.
    throw new ProviderError(
      "auth_failed",
      "OpenAI would not read your usage. This needs an organisation Admin key, not a project or user key.",
    );
  }
  if (!response.ok) throw await errorForResponse(HOST, response);
  return response.json<T>();
}

/**
 * Walks every page of one endpoint, flattening buckets to dated rows.
 *
 * The cap is a second line of defence behind `planWalk`: that plans for the
 * *expected* bucket count, and a provider that returns fewer buckets per page
 * than documented would otherwise turn a planned four requests into an
 * unbounded loop.
 */
async function walk<R>(
  ctx: AdapterContext,
  creds: OpenAICredentials,
  path: string,
  params: Record<string, string>,
): Promise<{ at: Date; result: R }[]> {
  const rows: { at: Date; result: R }[] = [];
  let page: string | null = null;

  for (let i = 0; i < MAX_PAGES; i++) {
    const url = new URL(`${API}${path}`);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    if (creds.project_id) url.searchParams.append("project_ids[]", creds.project_id);
    if (page) url.searchParams.set("page", page);

    const body: Page<R> = await get<Page<R>>(ctx, creds, url);
    for (const bucket of body.data) {
      // Bucketed by the bucket's own start, not by when we read it. The point
      // of a dated row is that re-bucketing to a week lands it in the right one.
      const at = new Date(bucket.start_time * 1000);
      for (const result of bucket.results) rows.push({ at, result });
    }

    if (!body.has_more || !body.next_page) return rows;
    page = body.next_page;
  }

  return rows;
}

/** The provider-side bucket width that can serve this granularity. */
function bucketWidth(granularity: MetricRequest["granularity"]): "1h" | "1d" {
  return granularity === "hour" ? "1h" : "1d";
}

function unixSeconds(date: Date): string {
  return String(Math.floor(date.getTime() / 1000));
}

async function usage(
  ctx: AdapterContext,
  creds: OpenAICredentials,
  request: MetricRequest,
  /**
   * Which of the usage report's columns this metric is.
   *
   * Passed in rather than switched on `request.metric`, whose `default` arm
   * was unreachable: `fetchMetric` had already decided this was not spend.
   */
  pick: (result: UsageResult) => number,
): Promise<SeriesResult> {
  const width = bucketWidth(request.granularity);
  const plan = planWalk({
    from: request.from,
    to: request.to,
    comparePrevious: request.comparePrevious,
    bucketMs: width === "1h" ? HOUR_MS : DAY_MS,
    bucketsPerPage: PER_PAGE[width],
    maxPages: MAX_PAGES,
  });

  const rows = await walk<UsageResult>(ctx, creds, "/organization/usage/completions", {
    start_time: unixSeconds(plan.start),
    end_time: unixSeconds(request.to),
    bucket_width: width,
    limit: String(PER_PAGE[width]),
  });

  const events = rows.map((row) => ({ at: row.at, amount: pick(row.result) }));
  return series(ctx, events, request, plan.comparePrevious, null);
}

async function spend(
  ctx: AdapterContext,
  creds: OpenAICredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  if (request.granularity === "hour") {
    throw new ProviderError(
      "unsupported",
      "OpenAI reports cost once a day. Pick a range of 7 days or longer.",
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

  const rows = await walk<CostResult>(ctx, creds, "/organization/costs", {
    start_time: unixSeconds(plan.start),
    end_time: unixSeconds(request.to),
    limit: String(PER_PAGE["1d"]),
  });

  // Other currencies are excluded rather than converted. OpenAI bills in USD
  // today, so this is a guard against a future that silently sums at 1:1.
  const foreign = new Set<string>();
  const events = rows.flatMap((row) => {
    const amount = row.result.amount;
    if (!amount) return [];
    if (amount.currency.toUpperCase() !== "USD") {
      foreign.add(amount.currency.toUpperCase());
      return [];
    }
    // `value` is dollars as a float. Minor units are taken per bucket rather
    // than per line item, so a day of thousandth-of-a-cent rows rounds once.
    return [{ at: row.at, amount: amount.value * 100 }];
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

/**
 * Buckets dated rows into the shape the notch renders.
 *
 * `value` is the total over the window and `previousValue` the total over the
 * window before it — both of these are flow metrics, unlike a subscription
 * book, so the sum is the right headline.
 */
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

const { series: seriesMetric } = metricsFor<OpenAICredentials>();

/**
 * One of the four usage metrics.
 *
 * All four walk the same completions report and differ only in which column
 * they add up — the argument, where it used to be a `pick` switch.
 */
function usageMetric(options: {
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
    // Hourly is real on the usage report. Spend below is daily-only, which
    // is why the two declare different sets rather than one generous one.
    granularities: ["hour", "day", "week"],
    compare: true,
    freshnessSeconds: 300,
    methodology: options.methodology,
    fetch: (ctx, creds, request: MetricRequest) => usage(ctx, creds, request, options.pick),
  });
}

export const tokens = usageMetric({
  id: "tokens",
  label: "Tokens",
  shortLabel: "Tokens",
  methodology:
    "Input plus output tokens on chat and completions requests in the window. Input includes cached reads and cache writes, so this matches what the Usage page totals rather than what you were charged for.",
  pick: (result) => result.input_tokens + result.output_tokens,
});

export const inputTokens = usageMetric({
  id: "input_tokens",
  label: "Input tokens",
  shortLabel: "Input",
  methodology:
    "Input tokens on completions requests, cached reads and cache writes included. Audio and image inputs are counted in their own token units, as OpenAI reports them.",
  pick: (result) => result.input_tokens,
});

export const outputTokens = usageMetric({
  id: "output_tokens",
  label: "Output tokens",
  shortLabel: "Output",
  methodology: "Output tokens generated on completions requests in the window.",
  pick: (result) => result.output_tokens,
});

export const apiRequests = usageMetric({
  id: "api_requests",
  label: "API requests",
  shortLabel: "Requests",
  methodology:
    "Model requests on the completions endpoint. One batch job counts as the requests inside it, not as one.",
  pick: (result) => result.num_model_requests,
});

export const apiSpend = seriesMetric({
  id: "api_spend",
  label: "API spend",
  shortLabel: "Spend",
  unit: "currency",
  // Daily-only, so `hour` is absent where the usage metrics have it and
  // `24h` is never offered. Declaring it would be the "too generous" half of
  // the range bug this connector shipped with.
  granularities: ["day", "week"],
  compare: true,
  freshnessSeconds: 300,
  methodology:
    "Billed cost per day from OpenAI's cost report, every line item included: tokens, tools and storage. Rounded to the cent per day, so it tracks the invoice rather than the fractional amounts the API returns.",
  fetch: spend,
});

export const openai = provider({
  metrics: [tokens, inputTokens, outputTokens, apiRequests, apiSpend],
  manifest,
  credentialSchema,

  async verify(ctx, creds) {
    // Yesterday onwards, one bucket. The window does not matter — this call
    // exists to prove the key is an admin key before a row is written, and an
    // organisation with no traffic yesterday still answers 200 with an empty
    // bucket.
    const usage = new URL(`${API}/organization/usage/completions`);
    usage.searchParams.set("start_time", unixSeconds(new Date(ctx.now().getTime() - DAY_MS)));
    usage.searchParams.set("bucket_width", "1d");
    usage.searchParams.set("limit", "1");
    if (creds.project_id) usage.searchParams.append("project_ids[]", creds.project_id);
    await get<Page<UsageResult>>(ctx, creds, usage);

    // Spend is withheld on refusal rather than the four token metrics being
    // listed on success: `provider()` derives what is available from the
    // metrics, so `verify` says only what this key cannot reach.
    let spendUnavailable = false;
    let accountLabel = creds.project_id ?? null;

    // Cost is a separate permission from usage on a scoped admin key. Narrowed
    // rather than fatal: a key that can read tokens but not dollars is still
    // worth four working widgets.
    try {
      const costs = new URL(`${API}/organization/costs`);
      costs.searchParams.set("start_time", unixSeconds(new Date(ctx.now().getTime() - DAY_MS)));
      costs.searchParams.set("limit", "1");
      const body = await get<Page<CostResult>>(ctx, creds, costs);
      accountLabel =
        body.data.flatMap((bucket) => bucket.results).find((r) => r.organization_id)
          ?.organization_id ?? accountLabel;
    } catch (error) {
      // A permanent refusal narrows; a transient one is fatal.
      //
      // `availableMetrics` is written once at connect time, so swallowing a
      // 500 or a rate limit would hide spend permanently over a bad thirty
      // seconds. But re-throwing everything else lets an *optional* probe
      // fail the whole connection — which is exactly what a malformed cost
      // request did on the Claude connector, leaving it unconnectable while
      // all four token metrics worked.
      const permanent = new Set(["auth_failed", "bad_response", "unsupported", "not_found"]);
      if (!(error instanceof ProviderError) || !permanent.has(error.code)) throw error;
      spendUnavailable = true;
      ctx.log("openai cost report refused, narrowing metrics", {
        code: error.code,
        message: error.message,
      });
    }

    return {
      accountLabel,
      currency: "USD",
      ...(spendUnavailable ? { unavailableMetrics: ["api_spend" as MetricId] } : {}),
    };
  },
});
