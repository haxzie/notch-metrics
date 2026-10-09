import { z } from "zod";
import type { Granularity, MetricId, ProviderManifest } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { dayAt, ymd } from "../../normalise.ts";
import type {
  AdapterContext,
  HttpResponse,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";

const HOST = "api.ahrefs.com";
const API = `https://${HOST}/v3`;

export const manifest: ProviderManifest = {
  id: "ahrefs",
  name: "Ahrefs",
  category: "marketing",
  tagline: "Backlinks, domain rating and organic keywords from Ahrefs.",
  docsUrl: "https://docs.ahrefs.com/en/api/docs/api-keys-creation-and-management",
  iconPath: "/providers/ahrefs.svg",
  accentColor: "#FF8C00",
  keywords: ["seo", "backlinks", "keywords", "domain rating"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API token",
      type: "secret",
      required: true,
      help: "Account Settings → API keys. Ahrefs bills per API row.",
    },
    {
      key: "target",
      label: "Domain",
      type: "string",
      required: true,
      placeholder: "example.com",
      help: "The domain to report on. Subdomains are included, as in Site Explorer.",
    },
  ],
  metrics: [
    {
      id: "backlinks",
      label: "Backlinks",
      shortLabel: "Links",
      unit: "count",
      granularities: ["day", "week", "month"],
      // Ahrefs publishes no backlinks history endpoint — only a count as at
      // one date. A sparkline would mean one billed request per bucket, so
      // this is a snapshot with an optional second reading for the delta.
      supportsSeries: false,
      supportsCompare: true,
      methodology: "Live external links pointing at the domain, as at the end of the window.",
    },
    {
      id: "domain_rating",
      label: "Domain rating",
      shortLabel: "DR",
      // `count`, not `ratio`: a ratio renders as value × 100 with a percent
      // sign, which turns a DR of 70 into "7000%". The series carries a
      // format override so it reads as a whole number and never compacts.
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Ahrefs' 0-100 strength score for the domain, at the end of the window.",
    },
    {
      id: "organic_keywords",
      label: "Organic keywords",
      shortLabel: "Keywords",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Keywords the domain ranks for in the top 100 organic results, at the end of the window.",
    },
  ],
  allowedHosts: [HOST],
  // Beta rather than stable: every endpoint here is implemented against the
  // documented v3 shapes and covered by tests, but nothing has yet run
  // against a live Ahrefs subscription.
  status: "beta",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  target: z.string().min(1),
});
export type AhrefsCredentials = z.infer<typeof credentialSchema>;

/**
 * The domain as Ahrefs wants it: no scheme, no path, no trailing dot.
 *
 * People paste what is in their address bar. Ahrefs accepts a URL as a
 * target, but a target of `https://example.com/` is scoped to that one page
 * rather than the site, so a pasted URL would silently report a DR of 0 and
 * no backlinks for a domain that plainly has both.
 */
function normaliseTarget(raw: string): string {
  const trimmed = raw.trim().replace(/^[a-z][a-z0-9+.-]*:\/\//i, "");
  const host = trimmed.split("/")[0] ?? "";
  return host.toLowerCase().replace(/\.$/, "");
}

/** Ahrefs groups history its own way; our `hour` has no counterpart. */
function grouping(granularity: Granularity): "daily" | "weekly" | "monthly" {
  switch (granularity) {
    case "hour":
    case "day":
      return "daily";
    case "week":
      return "weekly";
    case "month":
      return "monthly";
  }
}

async function get<T>(
  ctx: AdapterContext,
  creds: AhrefsCredentials,
  path: string,
  params: Record<string, string> = {},
): Promise<T> {
  const url = new URL(`${API}${path}`);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);

  const response = await ctx.http(url.toString(), {
    headers: { authorization: `Bearer ${creds.api_key}`, accept: "application/json" },
  });
  if (!response.ok) throw errorFor(response);
  return response.json<T>();
}

/**
 * Ahrefs answers 403 for a key that is real but on a plan without API
 * access, which `errorForStatus` would report as "rejected the credentials"
 * — sending somebody to regenerate a key that was never the problem.
 */
function errorFor(response: HttpResponse): ProviderError {
  if (response.status === 403) {
    return new ProviderError(
      "auth_failed",
      "Ahrefs refused the request. API access needs an eligible paid plan, and the key needs units left for this billing month.",
    );
  }
  return errorForStatus(HOST, response);
}

interface LimitsAndUsage {
  limits_and_usage?: {
    subscription?: string;
    units_limit_api_key?: number | null;
    units_usage_api_key?: number;
  };
}

interface DomainRatingHistory {
  domain_ratings?: { date: string; domain_rating: number }[];
}

interface KeywordsHistory {
  keywords?: { date: string; top3?: number; top4_10?: number; top11_plus?: number }[];
}

interface BacklinksStats {
  metrics?: { live?: number; all_time?: number; live_refdomains?: number };
}

/** A dated reading, oldest first — what both history endpoints reduce to. */
interface Reading {
  at: Date;
  v: number;
}

export const ahrefs: ProviderAdapter<AhrefsCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    // `limits-and-usage` rather than a reading of the domain: it is the one
    // endpoint Ahrefs serves free, and every other call costs a minimum of
    // 50 non-refundable units. Charging somebody for pressing Connect — and
    // again for every mistyped domain — is not a reasonable way to find out
    // that their key is valid.
    const body = await get<LimitsAndUsage>(ctx, creds, "/subscription-info/limits-and-usage");
    const limits = body.limits_and_usage;
    if (!limits) {
      throw new ProviderError("bad_response", "Ahrefs did not report this key's subscription.");
    }

    const target = normaliseTarget(creds.target);
    if (!target) {
      throw new ProviderError("unsupported", "That does not look like a domain.");
    }

    // Deliberately not checked against the key: Ahrefs has data on every
    // domain, not only the user's own, so there is nothing here that a
    // second billed call could confirm. A typo shows up as a DR of 0 on the
    // tile, which is the same thing it shows in Site Explorer.
    return {
      accountLabel: target,
      currency: null,
      availableMetrics: ["backlinks", "domain_rating", "organic_keywords"] as MetricId[],
    };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    switch (request.metric) {
      case "domain_rating":
        return domainRating(ctx, creds, request);
      case "organic_keywords":
        return organicKeywords(ctx, creds, request);
      case "backlinks":
        return backlinks(ctx, creds, request);
      default:
        throw new ProviderError("unsupported", `Ahrefs does not provide ${request.metric}.`);
    }
  },
};

/**
 * One history call covering the compare window as well as the current one.
 *
 * Asking twice would double a 50-unit floor for data the first response
 * already contains, so the range is widened and split here instead.
 */
async function history(
  ctx: AdapterContext,
  creds: AhrefsCredentials,
  request: MetricRequest,
  path: string,
  read: (body: unknown) => Reading[],
  extraParams: Record<string, string> = {},
): Promise<{ current: Reading[]; previous: Reading[] }> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const start = request.comparePrevious
    ? new Date(request.from.getTime() - windowMs)
    : request.from;

  const body = await get<unknown>(ctx, creds, path, {
    target: normaliseTarget(creds.target),
    date_from: ymd(start, ctx.timeZone),
    date_to: ymd(request.to, ctx.timeZone),
    history_grouping: grouping(request.granularity),
    ...extraParams,
  });

  const readings = read(body).sort((a, b) => a.at.getTime() - b.at.getTime());
  return {
    current: readings.filter((r) => r.at.getTime() >= request.from.getTime()),
    // Gated on the flag rather than on what came back. Ahrefs returning a
    // reading from before `date_from` would otherwise become a delta against
    // a window nobody asked about — and the widget would quietly start
    // showing an arrow that is not in its settings.
    previous: request.comparePrevious
      ? readings.filter((r) => r.at.getTime() < request.from.getTime())
      : [],
  };
}

/**
 * The last reading, not the sum.
 *
 * DR and keyword counts are stocks: the figure is what the domain is worth
 * at the end of the window, and adding up a month of daily readings would
 * report a DR in the thousands.
 */
function latest(readings: Reading[]): number {
  return readings.length === 0 ? 0 : (readings[readings.length - 1]?.v ?? 0);
}

async function domainRating(
  ctx: AdapterContext,
  creds: AhrefsCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const { current, previous } = await history(
    ctx,
    creds,
    request,
    "/site-explorer/domain-rating-history",
    (body) =>
      ((body as DomainRatingHistory).domain_ratings ?? []).map((row) => ({
        at: dayAt(row.date),
        v: row.domain_rating,
      })),
  );

  return {
    unit: "count",
    currency: null,
    points: current.map((r) => ({ t: r.at, v: r.v })),
    value: latest(current),
    previousValue: previous.length > 0 ? latest(previous) : null,
    asOf: current[current.length - 1]?.at,
    // Whole numbers and never abbreviated: DR is a 0-100 score, so "70" is
    // right and both "70.4" and a compacted "0.1k" are not.
    format: { decimals: 0, compact: false },
  };
}

async function organicKeywords(
  ctx: AdapterContext,
  creds: AhrefsCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const { current, previous } = await history(
    ctx,
    creds,
    request,
    "/site-explorer/keywords-history",
    (body) =>
      ((body as KeywordsHistory).keywords ?? []).map((row) => ({
        at: dayAt(row.date),
        // Ahrefs reports keywords split by SERP position, never as a total.
        // These three buckets partition the top 100; `top11_plus` already
        // contains `top21_50` and `top51_plus`, so asking for those as well
        // would count the same keyword twice.
        v: (row.top3 ?? 0) + (row.top4_10 ?? 0) + (row.top11_plus ?? 0),
      })),
    { select: "date,top3,top4_10,top11_plus", mode: "subdomains" },
  );

  return {
    unit: "count",
    currency: null,
    points: current.map((r) => ({ t: r.at, v: r.v })),
    value: latest(current),
    previousValue: previous.length > 0 ? latest(previous) : null,
    asOf: current[current.length - 1]?.at,
  };
}

async function backlinks(
  ctx: AdapterContext,
  creds: AhrefsCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const target = normaliseTarget(creds.target);
  const count = async (at: Date): Promise<number> => {
    const body = await get<BacklinksStats>(ctx, creds, "/site-explorer/backlinks-stats", {
      target,
      date: ymd(at, ctx.timeZone),
      mode: "subdomains",
    });
    // `live` rather than `all_time`: all-time counts links that no longer
    // exist, so it only ever rises and a lost link never shows.
    return body.metrics?.live ?? 0;
  };

  const value = await count(request.to);
  const previousValue = request.comparePrevious ? await count(request.from) : null;

  return {
    unit: "count",
    currency: null,
    // One point rather than a flat line across the window. There is no
    // history to draw, and inventing one would look like data.
    points: [{ t: request.to, v: value }],
    value,
    previousValue,
    asOf: request.to,
  };
}
