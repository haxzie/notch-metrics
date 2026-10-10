import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { toMinorUnits } from "../../normalise.ts";
import type {
  AdapterContext,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

const BASE = "https://api.revenuecat.com/v2";
const HOST = "api.revenuecat.com";

export const credentialSchema = z.object({
  // v1 keys are accepted by the field and rejected by RevenueCat with a 401,
  // which `verify` turns into a plain "rejected the credentials". The help
  // text says V2; a length floor is all the schema can honestly check.
  secret_key: z.string().min(20),
  project_id: z
    .string()
    .regex(/^[A-Za-z0-9_-]+$/, "A RevenueCat project ID looks like proj1ab2c3d4.")
    .optional()
    // An empty text field arrives as "", which is not an id and is not the
    // same as "not provided". Normalise before anything branches on it.
    .or(z.literal("").transform(() => undefined)),
});
export type RevenueCatCredentials = z.infer<typeof credentialSchema>;

/**
 * The currencies RevenueCat will report in. Anything else is a 400, so the
 * request falls back to the project's default and the response says which
 * currency it actually used.
 */
const REPORTING_CURRENCIES = new Set([
  "USD",
  "EUR",
  "GBP",
  "AUD",
  "CAD",
  "JPY",
  "BRL",
  "KRW",
  "CNY",
  "MXN",
  "SEK",
  "PLN",
  "NZD",
  "CHF",
]);

/**
 * RevenueCat reports money as a decimal in major units; ours is integer minor
 * units.
 *
 * Re-exported rather than defined here, which it used to be with a
 * two-currency exception list. One table, so Shopify's ¥ and RevenueCat's
 * cannot disagree about where the decimal point is.
 */
export { toMinorUnits };

interface Project {
  id: string;
  name: string;
}

interface ProjectList {
  items: Project[];
  next_page?: string | null;
}

interface OverviewMetric {
  id: string;
  name: string;
  unit: string;
  /** `P0D` is a snapshot; `P28D` is a rolling 28-day window. */
  period: string;
  value: number;
  last_updated_at: number | null;
}

interface Overview {
  metrics: OverviewMetric[];
  currency: string;
}

interface RevenueMetric {
  start_date: string;
  end_date: string;
  currency: string;
  value: number;
}

async function get<T>(
  ctx: AdapterContext,
  creds: RevenueCatCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  const url = new URL(`${BASE}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  const response = await ctx.http(url.toString(), { headers: headers(creds) });
  if (!response.ok) throw errorForStatus(HOST, response);
  return response.json<T>();
}

function headers(creds: RevenueCatCredentials): Record<string, string> {
  return {
    // v2 insists on the scheme. A bare key, which v1 accepted, is a 401
    // that reads as a wrong key rather than a malformed header.
    authorization: `Bearer ${creds.secret_key}`,
    accept: "application/json",
  };
}

function currencyParam(ctx: AdapterContext): string | undefined {
  const want = ctx.preferredCurrency.toUpperCase();
  return REPORTING_CURRENCIES.has(want) ? want : undefined;
}

/**
 * Which project the numbers come from.
 *
 * Metrics are per project, so a key that can see several has to say which.
 * Picking the first silently would show one app's MRR under another's name,
 * which is worse than asking.
 */
async function resolveProject(
  ctx: AdapterContext,
  creds: RevenueCatCredentials,
): Promise<{ id: string; label: string }> {
  const url = new URL(`${BASE}/projects`);
  url.searchParams.set("limit", "100");
  const response = await ctx.http(url.toString(), { headers: headers(creds) });

  // 403 and 401 are different answers here. RevenueCat says 401 for a key it
  // does not recognise and 403 for one that lacks the permission — and a
  // Charts-only key, the least privilege our metrics need, is exactly the
  // second case. Folding both into "bad key" would tell somebody with a
  // perfectly good key to go and make another one.
  if (response.status === 403) {
    if (!creds.project_id) {
      throw new ProviderError(
        "unsupported",
        "This key cannot list projects. Enter the project ID, or grant it Projects read.",
      );
    }
    ctx.log("revenuecat key cannot list projects; using the id as the label");
    return { id: creds.project_id, label: `Project ${creds.project_id}` };
  }
  if (!response.ok) throw errorForStatus(HOST, response);

  const projects = (await response.json<ProjectList>()).items ?? [];

  if (creds.project_id) {
    const chosen = projects.find((project) => project.id === creds.project_id);
    if (!chosen) {
      throw new ProviderError("unsupported", `This key cannot see project ${creds.project_id}.`);
    }
    return { id: chosen.id, label: chosen.name };
  }

  const first = projects[0];
  if (!first) throw new ProviderError("unsupported", "This key can see no projects.");
  if (projects.length > 1) {
    const names = projects.map((project) => `${project.name} (${project.id})`).join(", ");
    throw new ProviderError(
      "unsupported",
      `This key can see ${projects.length} projects. Enter the Project ID of one: ${names}.`,
    );
  }
  return { id: first.id, label: first.name };
}

async function overview(
  ctx: AdapterContext,
  creds: RevenueCatCredentials,
  projectId: string,
): Promise<Overview> {
  return get<Overview>(ctx, creds, `/projects/${encodeURIComponent(projectId)}/metrics/overview`, {
    currency: currencyParam(ctx),
  });
}

export const revenuecat: ProviderAdapter<RevenueCatCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    const project = await resolveProject(ctx, creds);

    // Proves `charts_metrics:overview:read`, which every metric here needs. A
    // key without it would otherwise become a row that fails on first poll.
    const metrics = await overview(ctx, creds, project.id);

    return {
      accountLabel: project.label,
      currency: metrics.currency?.toUpperCase() ?? null,
      availableMetrics: [
        "mrr",
        "revenue",
        "active_subscribers",
        "trials",
        "new_users",
        "active_users",
      ] satisfies MetricId[],
    };
  },

  async fetchMetric(ctx, creds, request): Promise<RawSeries> {
    const project = await projectIdFor(ctx, creds);
    switch (request.metric) {
      case "mrr":
        return fromOverview(ctx, creds, project, "mrr", "currency");
      case "active_subscribers":
        return fromOverview(ctx, creds, project, "active_subscriptions", "count");
      case "trials":
        return fromOverview(ctx, creds, project, "active_trials", "count");
      case "new_users":
        return fromOverview(ctx, creds, project, "new_customers", "count");
      case "active_users":
        return fromOverview(ctx, creds, project, "active_users", "count");
      case "revenue":
        return revenue(ctx, creds, project, request);
      default:
        throw new ProviderError("unsupported", `RevenueCat does not provide ${request.metric}.`);
    }
  },
};

/**
 * On a poll the project is already settled, so a key that can see exactly
 * one is resolved again only when nothing was typed — one extra request on a
 * 60/min domain, against a 25/min one for the metrics themselves.
 */
async function projectIdFor(ctx: AdapterContext, creds: RevenueCatCredentials): Promise<string> {
  if (creds.project_id) return creds.project_id;
  return (await resolveProject(ctx, creds)).id;
}

/**
 * One card off RevenueCat's Overview.
 *
 * The Overview is a fixed set of figures RevenueCat has already computed, so
 * a window is meaningless here: the snapshots are "now" and the 28-day cards
 * are 28 days whatever the widget asked for. The manifest says so.
 */
async function fromOverview(
  ctx: AdapterContext,
  creds: RevenueCatCredentials,
  projectId: string,
  id: string,
  unit: "currency" | "count",
): Promise<RawSeries> {
  const body = await overview(ctx, creds, projectId);
  const metric = body.metrics?.find((candidate) => candidate.id === id);
  if (!metric || typeof metric.value !== "number") {
    throw new ProviderError("bad_response", `RevenueCat's overview did not include ${id}.`);
  }

  const currency = (body.currency ?? "USD").toUpperCase();
  const value =
    unit === "currency" ? toMinorUnits(metric.value, currency) : Math.round(metric.value);
  const asOf = metric.last_updated_at ? new Date(metric.last_updated_at) : ctx.now();

  return {
    unit,
    currency: unit === "currency" ? currency : null,
    points: [{ t: ctx.now(), v: value }],
    value,
    previousValue: null,
    asOf,
    note: currencyNote(ctx, currency, unit),
  };
}

/** Says so when RevenueCat could not report in the currency the user wanted. */
function currencyNote(
  ctx: AdapterContext,
  reported: string,
  unit: "currency" | "count",
): string | undefined {
  if (unit !== "currency") return undefined;
  const want = ctx.preferredCurrency.toUpperCase();
  return reported === want
    ? undefined
    : `RevenueCat cannot report in ${want}, so this is in ${reported}.`;
}

/** `YYYY-MM-DD` in the user's zone. RevenueCat's days are calendar days. */
function isoDay(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

/**
 * Gross revenue over the window, straight from the endpoint that backs the
 * dashboard's own figure.
 *
 * No series: the endpoint totals one inclusive date range per call and the
 * Charts domain allows 25 calls a minute, so a thirty-point sparkline is a
 * minute of budget per widget. The previous window is one more call.
 */
async function revenue(
  ctx: AdapterContext,
  creds: RevenueCatCredentials,
  projectId: string,
  request: MetricRequest,
): Promise<RawSeries> {
  const path = `/projects/${encodeURIComponent(projectId)}/metrics/revenue`;
  const total = (from: Date, to: Date) =>
    get<RevenueMetric>(ctx, creds, path, {
      start_date: isoDay(from, ctx.timeZone),
      end_date: isoDay(to, ctx.timeZone),
      currency: currencyParam(ctx),
      revenue_type: "revenue",
    });

  const current = await total(request.from, request.to);
  const currency = (current.currency ?? "USD").toUpperCase();
  const value = toMinorUnits(current.value, currency);

  let previousValue: number | null = null;
  if (request.comparePrevious) {
    const windowMs = request.to.getTime() - request.from.getTime();
    // Inclusive calendar days: the previous window ends the day before the
    // current one starts, or the boundary day is counted twice.
    const dayMs = 24 * 60 * 60 * 1000;
    const previousTo = new Date(request.from.getTime() - dayMs);
    const previous = await total(new Date(previousTo.getTime() - windowMs), previousTo);
    previousValue = toMinorUnits(previous.value, (previous.currency ?? currency).toUpperCase());
  }

  return {
    unit: "currency",
    currency,
    points: [{ t: request.to, v: value }],
    value,
    previousValue,
    note: currencyNote(ctx, currency, "currency"),
  };
}
