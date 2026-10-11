import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { bucketSum, planWalk } from "../../normalise.ts";
import type {
  AdapterContext,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
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
  if (!response.ok) throw errorForStatus(HOST, response);
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

export const openai: ProviderAdapter<OpenAICredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
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

    const available: MetricId[] = ["tokens", "input_tokens", "output_tokens", "api_requests"];
    let accountLabel = creds.project_id ?? null;

    // Cost is a separate permission from usage on a scoped admin key. Narrowed
    // rather than fatal: a key that can read tokens but not dollars is still
    // worth four working widgets.
    try {
      const costs = new URL(`${API}/organization/costs`);
      costs.searchParams.set("start_time", unixSeconds(new Date(ctx.now().getTime() - DAY_MS)));
      costs.searchParams.set("limit", "1");
      const body = await get<Page<CostResult>>(ctx, creds, costs);
      available.push("api_spend");
      accountLabel =
        body.data.flatMap((bucket) => bucket.results).find((r) => r.organization_id)
          ?.organization_id ?? accountLabel;
    } catch (error) {
      // Only a refusal narrows. A 500 or a rate limit here is transient, and
      // `availableMetrics` is written once at connect time — swallowing those
      // would hide spend permanently over a bad thirty seconds, with nothing
      // short of reconnecting to bring it back.
      if (!(error instanceof ProviderError) || error.code !== "auth_failed") throw error;
      ctx.log("openai cost report refused, narrowing metrics", { code: error.code });
    }

    return { accountLabel, currency: "USD", availableMetrics: available };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    if (request.metric === "api_spend") return spend(ctx, creds, request);
    return usage(ctx, creds, request);
  },
};

async function usage(
  ctx: AdapterContext,
  creds: OpenAICredentials,
  request: MetricRequest,
): Promise<RawSeries> {
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

  const pick = (result: UsageResult): number => {
    switch (request.metric) {
      case "tokens":
        return result.input_tokens + result.output_tokens;
      case "input_tokens":
        return result.input_tokens;
      case "output_tokens":
        return result.output_tokens;
      case "api_requests":
        return result.num_model_requests;
      default:
        throw new ProviderError("unsupported", `OpenAI does not provide ${request.metric}.`);
    }
  };

  const events = rows.map((row) => ({ at: row.at, amount: pick(row.result) }));
  return series(ctx, events, request, plan.comparePrevious, null);
}

async function spend(
  ctx: AdapterContext,
  creds: OpenAICredentials,
  request: MetricRequest,
): Promise<RawSeries> {
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
): RawSeries {
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
    unit: currency ? "currency" : "count",
    currency,
    points,
    value: Math.round(total(current)),
    previousValue: comparePrevious ? Math.round(total(previous)) : null,
    note,
  };
}
