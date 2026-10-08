import { z } from "zod";
import type { Granularity, MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { RECENT_PAYMENTS_LIMIT, recentPayments } from "../../list.ts";
import type {
  AdapterContext,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

export const credentialSchema = z.object({
  access_token: z.string().min(20),
  mode: z.enum(["production", "sandbox"]).default("production"),
});
export type PolarCredentials = z.infer<typeof credentialSchema>;

/**
 * The host is chosen by the declared mode, never inferred from the token.
 * Both environments issue `polar_oat_` tokens, so there is nothing to infer
 * from — and a production token against the sandbox is a 401 that reads as
 * a revoked key.
 */
function host(creds: PolarCredentials): string {
  return creds.mode === "sandbox" ? "sandbox-api.polar.sh" : "api.polar.sh";
}

interface Organization {
  id: string;
  name: string;
  slug: string;
  default_presentment_currency?: string | null;
}

interface Page<T> {
  items: T[];
  pagination?: { total_count?: number; max_page?: number };
}

/** Every value is nullable: a metric Polar did not compute for a period is null, not zero. */
interface MetricPeriod {
  timestamp: string;
  revenue?: number | null;
  monthly_recurring_revenue?: number | null;
  active_subscriptions?: number | null;
  new_subscriptions?: number | null;
  churned_subscriptions?: number | null;
}

interface MetricsResponse {
  periods: MetricPeriod[];
}

interface Order {
  id: string;
  created_at: string;
  status: string;
  paid?: boolean;
  total_amount: number;
  currency: string;
  description?: string | null;
  customer?: { name?: string | null; email?: string | null } | null;
  product?: { name?: string | null } | null;
}

async function get<T>(
  ctx: AdapterContext,
  creds: PolarCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  // Trailing slashes are canonical on Polar's list routes; without one the
  // API redirects, and the client refuses to follow a redirect with a key.
  const url = new URL(`https://${host(creds)}/v1${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  const response = await ctx.http(url.toString(), {
    headers: { authorization: `Bearer ${creds.access_token}`, accept: "application/json" },
  });
  if (!response.ok) throw errorForStatus(host(creds), response);
  return response.json<T>();
}

/**
 * The token's organization. A Polar organization token is bound to exactly
 * one organization, so the first item is the only item.
 */
async function organization(ctx: AdapterContext, creds: PolarCredentials): Promise<Organization> {
  const page = await get<Page<Organization>>(ctx, creds, "/organizations/", { limit: 1 });
  const org = page.items?.[0];
  if (!org) throw new ProviderError("unsupported", "This token can see no organization.");
  return org;
}

/** Polar reports its metrics in the organization's currency, and says so nowhere in the response. */
function currencyOf(org: Organization): string {
  return (org.default_presentment_currency ?? "USD").toUpperCase();
}

/** `YYYY-MM-DD` in the user's zone; Polar's periods are calendar periods in `timezone`. */
function isoDay(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export const polar: ProviderAdapter<PolarCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    const org = await organization(ctx, creds);

    // Scopes are per endpoint and a token can carry any subset. Narrowing to
    // what this token can read beats telling somebody their token is broken
    // because it lacks one scope they did not need.
    const available: MetricId[] = [];
    const scoped = async (probe: () => Promise<unknown>, grants: MetricId[]) => {
      try {
        await probe();
        available.push(...grants);
      } catch (error) {
        if (!(error instanceof ProviderError) || error.code !== "auth_failed") throw error;
        ctx.log(`polar token lacks a scope; not offering ${grants.join(", ")}`);
      }
    };
    await scoped(
      () => get(ctx, creds, "/metrics/limits"),
      ["mrr", "revenue", "active_subscribers", "new_subscribers", "churned_subscribers"],
    );
    await scoped(() => get(ctx, creds, "/orders/", { limit: 1 }), ["recent_payments"]);

    if (available.length === 0) {
      throw new ProviderError(
        "unsupported",
        "This token can read neither metrics nor orders. Grant it metrics:read and orders:read.",
      );
    }

    return {
      accountLabel: org.name,
      currency: currencyOf(org),
      availableMetrics: available,
    };
  },

  async fetchMetric(ctx, creds, request): Promise<RawSeries> {
    switch (request.metric) {
      case "mrr":
        return latest(ctx, creds, request, "monthly_recurring_revenue", "currency");
      case "active_subscribers":
        return latest(ctx, creds, request, "active_subscriptions", "count");
      case "revenue":
        return overWindow(ctx, creds, request, "revenue", "currency");
      case "new_subscribers":
        return overWindow(ctx, creds, request, "new_subscriptions", "count");
      case "churned_subscribers":
        return overWindow(ctx, creds, request, "churned_subscriptions", "count");
      case "recent_payments":
        return latestOrders(ctx, creds);
      default:
        throw new ProviderError("unsupported", `Polar does not provide ${request.metric}.`);
    }
  },
};

type Slug = keyof Omit<MetricPeriod, "timestamp">;

/** Polar's own interval names happen to match ours. */
const INTERVAL: Record<Granularity, string> = {
  hour: "hour",
  day: "day",
  week: "week",
  month: "month",
};

async function periods(
  ctx: AdapterContext,
  creds: PolarCredentials,
  slug: Slug,
  from: Date,
  to: Date,
  granularity: Granularity,
): Promise<MetricPeriod[]> {
  const body = await get<MetricsResponse>(ctx, creds, "/metrics/", {
    start_date: isoDay(from, ctx.timeZone),
    end_date: isoDay(to, ctx.timeZone),
    interval: INTERVAL[granularity],
    timezone: ctx.timeZone,
    // Only this metric's queries run server-side, which matters on an
    // endpoint that would otherwise compute fifty-odd figures per call.
    metrics: slug,
  });
  return body.periods ?? [];
}

/**
 * A snapshot: the most recent period Polar has a value for.
 *
 * Polar computes MRR and active subscriptions per period, and the last few
 * can be null while its pipeline catches up. Taking the last non-null value
 * rather than the last period keeps a tile from showing zero at midnight.
 */
async function latest(
  ctx: AdapterContext,
  creds: PolarCredentials,
  request: MetricRequest,
  slug: Slug,
  unit: "currency" | "count",
): Promise<RawSeries> {
  const org = await organization(ctx, creds);
  // A week of days, not the widget's window: the window could be a year at
  // month resolution, and the answer is "now", not "this month so far".
  const now = ctx.now();
  const rows = await periods(
    ctx,
    creds,
    slug,
    new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
    now,
    "day",
  );
  const last = [...rows].reverse().find((row) => typeof row[slug] === "number");
  const value = Math.round((last?.[slug] as number | undefined) ?? 0);

  return {
    unit,
    currency: unit === "currency" ? currencyOf(org) : null,
    points: [{ t: now, v: value }],
    value,
    previousValue: null,
    asOf: last ? new Date(last.timestamp) : now,
  };
}

/**
 * A total over the window, with the previous window for the delta.
 *
 * One call covers both windows: Polar buckets the whole span and the split
 * is done here by timestamp, which halves the calls on an endpoint with a
 * per-minute budget.
 */
async function overWindow(
  ctx: AdapterContext,
  creds: PolarCredentials,
  request: MetricRequest,
  slug: Slug,
  unit: "currency" | "count",
): Promise<RawSeries> {
  const org = await organization(ctx, creds);
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  const rows = await periods(ctx, creds, slug, from, request.to, request.granularity);
  const valued = rows.map((row) => ({
    t: new Date(row.timestamp),
    v: Math.round((row[slug] as number | null | undefined) ?? 0),
  }));

  const current = valued.filter((row) => row.t >= request.from);
  const previous = valued.filter((row) => row.t < request.from);
  const sum = (list: { v: number }[]) => list.reduce((total, row) => total + row.v, 0);

  return {
    unit,
    currency: unit === "currency" ? currencyOf(org) : null,
    points: request.wantSeries ? current : [],
    value: sum(current),
    previousValue: request.comparePrevious ? sum(previous) : null,
  };
}

/** Orders took payment. `pending` and `draft` did not; `void` never will. */
const PAID = new Set(["paid", "refunded", "partially_refunded"]);

async function latestOrders(ctx: AdapterContext, creds: PolarCredentials): Promise<RawSeries> {
  const page = await get<Page<Order>>(ctx, creds, "/orders/", {
    limit: RECENT_PAYMENTS_LIMIT * 2,
    sorting: "-created_at",
  });
  const rows = (page.items ?? [])
    .filter((order) => PAID.has(order.status))
    .map((order) => ({
      id: order.id,
      t: new Date(order.created_at),
      label: order.customer?.name || order.customer?.email || "Customer",
      detail: order.product?.name || order.description || null,
      amount: order.total_amount,
      currency: order.currency.toUpperCase(),
      status: order.status.replace("_", " "),
    }));
  return recentPayments(ctx, rows);
}
