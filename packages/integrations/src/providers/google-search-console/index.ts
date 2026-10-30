import { z } from "zod";
import type { Granularity, MetricId, ProviderManifest } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import {
  googleErrorReason,
  googleHeaders,
  googleOAuth,
  isGoogleQuotaReason,
} from "../../google-oauth.ts";
import { bucketStart, dayAt, ymd } from "../../normalise.ts";
import type {
  AdapterContext,
  HttpResponse,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { metricsFor, provider, type SeriesResult } from "../../metric.ts";
import { ProviderError } from "../../types.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "google-search-console",
  name: "Google Search Console",
  category: "marketing",
  tagline: "Clicks, impressions and ranking from Search Console.",
  docsUrl: "https://search.google.com/search-console",
  dashboardUrl: "https://search.google.com/search-console",
  iconPath: "/connectors/google-search-console.svg",
  accentColor: "#4285F4",
  keywords: ["gsc", "seo", "search", "google", "rankings", "queries"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your Search Console performance data"],
    requiresSelection: true,
    selectionLabel: "Which property?",
  },
  fields: [],
  allowedHosts: ["www.googleapis.com", "searchconsole.googleapis.com", "oauth2.googleapis.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  /** Exactly as Search Console names it: `https://example.com/` or `sc-domain:example.com`. */
  site: z.string().min(1),
  access_token: z.string().min(10),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.string().regex(/^\d+$/).optional(),
});
export type GoogleSearchConsoleCredentials = z.infer<typeof credentialSchema>;

const API = "https://www.googleapis.com/webmasters/v3";

/** Search Console data is never final for the newest days. Said once, on every series. */
const LAG_NOTE = "Search Console data runs two to three days behind.";

async function errorFor(response: HttpResponse): Promise<ProviderError> {
  if (response.status === 403) {
    // See the Google Analytics adapter: 403 is quota as often as permission,
    // and only the body says which.
    const reason = await googleErrorReason(response);
    if (isGoogleQuotaReason(reason)) {
      return new ProviderError("rate_limited", "Search Console's quota is spent", 900);
    }
    return new ProviderError(
      "auth_failed",
      "Google refused the request. Check the Search Console API is enabled and this account can see the property.",
    );
  }
  return errorForResponse("www.googleapis.com", response);
}

interface SiteEntry {
  siteUrl: string;
  permissionLevel: string;
}

interface QueryRow {
  keys: string[];
  clicks: number;
  impressions: number;
  ctr: number;
  position: number;
}

async function listSites(accessToken: string): Promise<SiteEntry[]> {
  const response = await fetch(`${API}/sites`, {
    redirect: "manual",
    headers: googleHeaders(accessToken),
  });
  if (!response.ok) {
    throw new ProviderError(
      "auth_failed",
      "We could not list your Search Console properties. Check the Search Console API is enabled.",
    );
  }
  const body = (await response.json()) as { siteEntry?: SiteEntry[] };
  // A site the account was added to but never verified answers every query
  // with nothing; it is not a choice worth offering.
  return (body.siteEntry ?? []).filter((s) => s.permissionLevel !== "siteUnverifiedUser");
}

async function query(
  ctx: AdapterContext,
  creds: GoogleSearchConsoleCredentials,
  from: Date,
  to: Date,
): Promise<QueryRow[]> {
  const response = await ctx.http(
    `${API}/sites/${encodeURIComponent(creds.site)}/searchAnalytics/query`,
    {
      method: "POST",
      headers: { ...googleHeaders(creds.access_token), "content-type": "application/json" },
      body: JSON.stringify({
        startDate: ymd(from, ctx.timeZone),
        endDate: ymd(to, ctx.timeZone),
        dimensions: ["date"],
        // `all` includes the fresh, not-yet-final days. Without it the last
        // two days are simply absent and the chart ends in a cliff.
        dataState: "all",
        // One row per day; a year is 366. The cap is far above that.
        rowLimit: 1000,
      }),
    },
  );
  if (!response.ok) throw await errorFor(response);
  const body = await response.json<{ rows?: QueryRow[] }>();
  return body.rows ?? [];
}

/** Clicks, impressions and position summed so a rate or a mean can be taken over any span. */
interface Totals {
  clicks: number;
  impressions: number;
  /** Σ position × impressions, so the mean is weighted the way Google's is. */
  weightedPosition: number;
}

function add(into: Totals, row: QueryRow): void {
  into.clicks += row.clicks;
  into.impressions += row.impressions;
  into.weightedPosition += row.position * row.impressions;
}

/**
 * All four metrics come from the same rows; the request is identical and
 * only the arithmetic at the end differs. Rates and means are computed
 * from the summed components per bucket, never averaged from daily rates.
 */
async function performance(
  ctx: AdapterContext,
  creds: GoogleSearchConsoleCredentials,
  request: MetricRequest,
  /**
   * The arithmetic that turns summed components into this metric's number.
   *
   * Passed in rather than switched on `request.metric`, which is what
   * `figure()` did — a fifth place the four ids were written out, and one
   * whose `default` arm was unreachable because the switch above had
   * already filtered.
   */
  figure: (totals: Totals) => number,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const rows = await query(ctx, creds, request.from, request.to);
  const previousRows = request.comparePrevious
    ? await query(
        ctx,
        creds,
        new Date(request.from.getTime() - windowMs),
        new Date(request.from.getTime() - 1),
      )
    : null;

  const points = bucket(rows, figure, request.granularity, request, ctx.timeZone);
  const sum = (set: QueryRow[]): Totals => {
    const totals: Totals = { clicks: 0, impressions: 0, weightedPosition: 0 };
    for (const row of set) add(totals, row);
    return totals;
  };

  return {
    points,
    value: figure(sum(rows)),
    previousValue: previousRows ? figure(sum(previousRows)) : null,
    note: LAG_NOTE,
  };
}

/** Gap-filled like `bucketSum`, but each bucket carries components rather than one sum. */
function bucket(
  rows: QueryRow[],
  figure: (totals: Totals) => number,
  granularity: Granularity,
  window: { from: Date; to: Date },
  timeZone: string,
): { t: Date; v: number }[] {
  const byBucket = new Map<number, Totals>();
  for (const row of rows) {
    const day = dayAt(row.keys[0] ?? "");
    if (Number.isNaN(day.getTime())) continue;
    const key = bucketStart(day, granularity, timeZone).getTime();
    const totals = byBucket.get(key) ?? { clicks: 0, impressions: 0, weightedPosition: 0 };
    add(totals, row);
    byBucket.set(key, totals);
  }

  const points: { t: Date; v: number }[] = [];
  let cursor = bucketStart(window.from, granularity, timeZone);
  const end = bucketStart(window.to, granularity, timeZone);
  for (let i = 0; cursor <= end && i < 1000; i++) {
    const totals = byBucket.get(cursor.getTime());
    points.push({ t: new Date(cursor), v: totals ? figure(totals) : 0 });
    cursor = bucketStart(
      new Date(cursor.getTime() + stride(granularity) + 1),
      granularity,
      timeZone,
    );
  }
  return points;
}

/** Enough to land in the next bucket; `bucketStart` snaps it back. */
function stride(granularity: Granularity): number {
  switch (granularity) {
    case "hour":
      return 60 * 60 * 1000;
    case "day":
      return 24 * 60 * 60 * 1000;
    case "week":
      return 7 * 24 * 60 * 60 * 1000;
    case "month":
      return 31 * 24 * 60 * 60 * 1000;
  }
}

const { series } = metricsFor<GoogleSearchConsoleCredentials>();

/**
 * One Search Console metric.
 *
 * All four come from the same rows and the same request; only the arithmetic
 * at the end differs, which is why that arithmetic is the argument. It used
 * to be a `figure()` switch keyed on metric id — the fourth list of these
 * four ids in the file.
 */
function searchMetric(options: {
  id: MetricId;
  label: string;
  shortLabel: string;
  unit: "count" | "ratio";
  methodology: string;
  figure: (totals: Totals) => number;
  /** Search Console's average position is 12.3, not 12 — see `MetricFormat`. */
  format?: { decimals: number; compact: boolean };
}) {
  return series({
    id: options.id,
    label: options.label,
    shortLabel: options.shortLabel,
    unit: options.unit,
    granularities: ["day", "week", "month"],
    compare: true,
    methodology: options.methodology,

    async fetch(ctx, creds, request: MetricRequest): Promise<SeriesResult> {
      const result = await performance(ctx, creds, request, options.figure);
      return options.format ? { ...result, format: options.format } : result;
    },
  });
}

export const clicks = searchMetric({
  id: "clicks",
  label: "Clicks",
  shortLabel: "Clicks",
  unit: "count",
  methodology:
    "Clicks through to the site from Google Search in the window. Search Console data runs two to three days behind, so the newest days read low until they settle.",
  figure: (totals) => totals.clicks,
});

export const impressions = searchMetric({
  id: "impressions",
  label: "Impressions",
  shortLabel: "Impr.",
  unit: "count",
  methodology: "Times a result for the site was shown in the window. Two to three days behind.",
  figure: (totals) => totals.impressions,
});

export const ctr = searchMetric({
  id: "ctr",
  label: "Click-through rate",
  shortLabel: "CTR",
  unit: "ratio",
  methodology:
    "Clicks divided by impressions over the window, rather than the mean of daily rates, which would weight a quiet day the same as a busy one.",
  // Over the window's components, never the mean of daily rates.
  figure: (totals) => (totals.impressions === 0 ? 0 : totals.clicks / totals.impressions),
});

export const averagePosition = searchMetric({
  id: "average_position",
  label: "Average position",
  shortLabel: "Position",
  unit: "count",
  methodology:
    "Mean ranking position across impressions in the window, weighted by impressions the way Search Console's own overview is. Lower is better.",
  figure: (totals) => (totals.impressions === 0 ? 0 : totals.weightedPosition / totals.impressions),
  format: { decimals: 1, compact: false },
});

export const googleSearchConsole = provider({
  metrics: [clicks, impressions, ctr, averagePosition],
  manifest,
  credentialSchema,
  // Tokens arrive from the OAuth callback and are never typed in. Without
  // this the connect page would render an access token as a text box.
  userInputFields: [],

  oauth: googleOAuth<GoogleSearchConsoleCredentials>({
    scopes: ["https://www.googleapis.com/auth/webmasters.readonly"],
    scopeSummary: ["Read your Search Console performance data"],
    empty: { site: "" },
    selection: {
      label: "Which property?",
      field: "site",
      async options(credentials) {
        return (await listSites(credentials.access_token)).map((s) => ({
          value: s.siteUrl,
          // "sc-domain:example.com" is how Search Console names a domain
          // property; shown as-is so it matches what the user sees there.
          label: s.siteUrl,
          hint: s.permissionLevel === "siteOwner" ? "Owner" : undefined,
        }));
      },
    },
  }),

  async verify(ctx, creds) {
    // The list rather than a query: a query on a site the account cannot
    // see answers 403 like everything else, but the list also catches the
    // site being gone — and it is one call either way.
    const sites = await listSites(creds.access_token);
    if (!sites.some((s) => s.siteUrl === creds.site)) {
      throw new ProviderError(
        "auth_failed",
        "That Search Console property is not on this Google account any more.",
      );
    }
    // No `availableMetrics`: it was these four ids written out a second
    // time, beside the manifest and the switch. Derived from the metrics now.
    return {
      accountLabel: creds.site.replace(/^sc-domain:/, "").replace(/\/$/, ""),
      currency: null,
    };
  },
});
