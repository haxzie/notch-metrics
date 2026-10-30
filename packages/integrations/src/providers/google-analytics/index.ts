import { z } from "zod";
import type { MetricId, ProviderManifest } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import {
  googleErrorReason,
  googleHeaders,
  googleOAuth,
  isGoogleQuotaReason,
} from "../../google-oauth.ts";
import { metricsFor, provider, type SeriesResult } from "../../metric.ts";
import { bucketSum, dayAt, ymd } from "../../normalise.ts";
import type { AdapterContext, HttpResponse, MetricRequest } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "google-analytics",
  name: "Google Analytics",
  category: "analytics",
  tagline: "Users, sessions and page views from GA4.",
  docsUrl: "https://analytics.google.com/analytics/web/",
  dashboardUrl: "https://analytics.google.com",
  iconPath: "/connectors/google-analytics.svg",
  accentColor: "#E8710A",
  keywords: ["ga4", "web analytics", "traffic", "google", "visitors"],
  // GA4's Data API is OAuth-only; there is no key to paste.
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your Google Analytics reports"],
    // Authorising grants every property on the account, so the user still
    // has to say which one this connection is for.
    requiresSelection: true,
    selectionLabel: "Which property?",
  },
  fields: [],
  allowedHosts: [
    "analyticsdata.googleapis.com",
    // Only for naming the property. The report itself is the Data API.
    "analyticsadmin.googleapis.com",
    "oauth2.googleapis.com",
  ],
  status: "stable",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  /** Chosen from the picker after authorising. Bare digits, no `properties/`. */
  property_id: z.string().regex(/^\d+$/, "A GA4 property ID is a number."),
  // Written by the OAuth callback, never by a form.
  access_token: z.string().min(10),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.string().regex(/^\d+$/).optional(),
});
export type GoogleAnalyticsCredentials = z.infer<typeof credentialSchema>;

const { series } = metricsFor<GoogleAnalyticsCredentials>();

const DATA = "https://analyticsdata.googleapis.com/v1beta";
const ADMIN = "https://analyticsadmin.googleapis.com/v1beta";

/**
 * 403 from Google is three different things: the API is not enabled on
 * the project, the account cannot see the property, or the token lost the
 * scope. All need a human; none is a rate limit. The message names the
 * first because it is the one a fresh deployment hits.
 */
async function errorFor(response: HttpResponse): Promise<ProviderError> {
  if (response.status === 403) {
    // Read Google's own reason before deciding. A spent quota and a missing
    // permission share this status, and only one of them is worth telling
    // somebody their connection is broken over.
    const reason = await googleErrorReason(response);
    if (isGoogleQuotaReason(reason)) {
      return new ProviderError("rate_limited", "Google's analytics quota is spent", 900);
    }
    return new ProviderError(
      "auth_failed",
      "Google refused the request. Check the Google Analytics Data API is enabled and this account can see the property.",
    );
  }
  return errorForResponse("analyticsdata.googleapis.com", response);
}

/**
 * Every field optional, deliberately.
 *
 * Google's JSON encoding drops an empty repeated field rather than sending
 * `[]`, so a date range it found no data at all for arrives as a bare `{}` in
 * `totals` — no `dimensionValues`, no `metricValues`. Typing those as present
 * is what let `.dimensionValues.some(...)` throw a `TypeError` on a response
 * that is entirely well formed.
 */
interface ReportRow {
  dimensionValues?: { value: string }[];
  metricValues?: { value: string }[];
}

interface RunReportResponse {
  rows?: ReportRow[];
  totals?: ReportRow[];
}

async function runReport(
  ctx: AdapterContext,
  creds: GoogleAnalyticsCredentials,
  body: Record<string, unknown>,
): Promise<RunReportResponse> {
  const response = await ctx.http(`${DATA}/properties/${creds.property_id}:runReport`, {
    method: "POST",
    headers: { ...googleHeaders(creds.access_token), "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw await errorFor(response);
  return response.json<RunReportResponse>();
}

/**
 * One request carries both windows. With two date ranges GA appends a
 * `dateRange` dimension to every row, and `totals` carries one row per
 * range — which is where the headline comes from, because GA de-duplicates
 * users across the range there and a sum of daily rows would not.
 */
async function report(
  ctx: AdapterContext,
  creds: GoogleAnalyticsCredentials,
  metric: string,
  request: MetricRequest,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const ranges = [
    { startDate: ymd(request.from, ctx.timeZone), endDate: ymd(request.to, ctx.timeZone) },
  ];
  if (request.comparePrevious) {
    ranges.push({
      startDate: ymd(new Date(request.from.getTime() - windowMs), ctx.timeZone),
      endDate: ymd(new Date(request.from.getTime() - 1), ctx.timeZone),
    });
  }

  const body = await runReport(ctx, creds, {
    dateRanges: ranges,
    dimensions: [{ name: "date" }],
    metrics: [{ name: metric }],
    metricAggregations: ["TOTAL"],
    // Every day, even the silent ones — see bucketSum on why gaps matter.
    keepEmptyRows: true,
    limit: 10_000,
  });

  const events = (body.rows ?? [])
    // With a second range, the last dimension says which. Only the current
    // window feeds the chart.
    .filter((row) => ranges.length === 1 || row.dimensionValues?.[1]?.value === "date_range_0")
    .map((row) => ({
      at: dayAt(row.dimensionValues?.[0]?.value ?? ""),
      amount: Number(row.metricValues?.[0]?.value ?? 0),
    }))
    .filter((e) => !Number.isNaN(e.at.getTime()));

  const points = bucketSum(events, {
    from: request.from,
    to: request.to,
    granularity: request.granularity,
    timeZone: ctx.timeZone,
  });

  // A totals row carries RESERVED_TOTAL for the date and, with two ranges,
  // the range name as its last dimension — so the range is looked for
  // anywhere in the row rather than at a fixed index.
  //
  // Position is the fallback, and it is the case that matters: a range Google
  // found nothing in comes back as `{}`, with no name to match on, and
  // `totals` stays aligned with `dateRanges` regardless. That is the whole of
  // the 90d and 12m bug — a property younger than the comparison window the
  // tile asks for empties exactly one entry, and the tile answered "that
  // provider could not be reached" for a report that had arrived intact.
  //
  // An entry that is present but empty is a real zero, not a missing answer:
  // nobody visited in that window. Only a `totals` short enough not to have
  // the entry at all is unknown.
  const totals = body.totals ?? [];
  const total = (index: number): number | null => {
    const row =
      (ranges.length === 1
        ? totals[0]
        : totals.find((t) => t.dimensionValues?.some((v) => v.value === `date_range_${index}`))) ??
      totals[index];
    if (!row) return null;
    const value = row.metricValues?.[0]?.value;
    return value === undefined ? 0 : Number(value);
  };

  return {
    points,
    value: total(0) ?? events.reduce((sum, e) => sum + e.amount, 0),
    previousValue: request.comparePrevious ? total(1) : null,
  };
}

/**
 * One GA4 metric.
 *
 * All four ask for the same report and differ only in the name GA4 knows the
 * metric by — which used to live in a `METRICS` lookup the switch consulted,
 * one more table that had to agree with the manifest.
 */
function ga4Metric(options: {
  id: MetricId;
  label: string;
  shortLabel: string;
  /** GA4's own name for it: `activeUsers`, `screenPageViews`. */
  name: string;
  methodology: string;
}) {
  return series({
    id: options.id,
    label: options.label,
    shortLabel: options.shortLabel,
    unit: "count",
    granularities: ["day", "week", "month"],
    compare: true,
    methodology: options.methodology,
    fetch: (ctx, creds, request: MetricRequest): Promise<SeriesResult> =>
      report(ctx, creds, options.name, request),
  });
}

export const activeUsers = ga4Metric({
  id: "active_users",
  label: "Active users",
  shortLabel: "Users",
  name: "activeUsers",
  methodology:
    "GA4 `activeUsers`. The headline is the de-duplicated count over the whole window, as GA reports it; the chart is per day, so its bars do not add up to the headline: one person on three days is one user and three bars.",
});
export const newUsers = ga4Metric({
  id: "new_users",
  label: "New users",
  shortLabel: "New",
  name: "newUsers",
  methodology: "GA4 `newUsers`: people whose first session fell in the window.",
});
export const sessions = ga4Metric({
  id: "sessions",
  label: "Sessions",
  shortLabel: "Sessions",
  name: "sessions",
  methodology: "GA4 `sessions` in the window.",
});
export const pageviews = ga4Metric({
  id: "pageviews",
  label: "Page views",
  shortLabel: "Views",
  name: "screenPageViews",
  methodology: "GA4 `screenPageViews`: every page and screen view in the window.",
});

export const googleAnalytics = provider({
  metrics: [activeUsers, newUsers, sessions, pageviews],
  manifest,
  credentialSchema,
  // Empty, and explicit. Without it the connect page falls back to rendering
  // every schema field — which would put an access token in a text box.
  userInputFields: [],

  oauth: googleOAuth<GoogleAnalyticsCredentials>({
    scopes: ["https://www.googleapis.com/auth/analytics.readonly"],
    scopeSummary: ["Read your Google Analytics reports"],
    empty: { property_id: "" },
    selection: {
      label: "Which property?",
      field: "property_id",
      async options(credentials) {
        // Account summaries list every property the account can see in one
        // call, grouped by account — which is the hint, because two
        // properties called "Website" under different accounts are common.
        const response = await fetch(`${ADMIN}/accountSummaries?pageSize=200`, {
          redirect: "manual",
          headers: googleHeaders(credentials.access_token),
        });
        if (!response.ok) {
          throw new ProviderError(
            "auth_failed",
            "We could not list your Google Analytics properties. Check the Google Analytics Admin API is enabled.",
          );
        }
        const body = (await response.json()) as {
          accountSummaries?: {
            displayName: string;
            propertySummaries?: { property: string; displayName: string }[];
          }[];
        };
        return (body.accountSummaries ?? []).flatMap((account) =>
          (account.propertySummaries ?? []).map((p) => ({
            // "properties/123" → "123". The Data API path wants the number.
            value: p.property.replace(/^properties\//, ""),
            label: p.displayName,
            hint: account.displayName,
          })),
        );
      },
    },
  }),

  async verify(ctx, creds) {
    // One tiny report: proves the token, the scope, the API being enabled
    // and access to this property, which is everything a metric needs.
    const today = ymd(ctx.now(), ctx.timeZone);
    await runReport(ctx, creds, {
      dateRanges: [{ startDate: today, endDate: today }],
      metrics: [{ name: "activeUsers" }],
      limit: 1,
    });

    // Named after the property, so two connections can be told apart. Best
    // effort: a property is still connectable if the Admin API is not
    // enabled, it just reads as its number.
    let label = `Property ${creds.property_id}`;
    try {
      const response = await ctx.http(`${ADMIN}/properties/${creds.property_id}`, {
        headers: googleHeaders(creds.access_token),
      });
      if (response.ok) {
        const body = await response.json<{ displayName?: string }>();
        if (body.displayName) label = body.displayName;
      }
    } catch (error) {
      ctx.log("could not name the GA4 property", { error: String(error) });
    }

    // No `availableMetrics`: it was `Object.keys(METRICS)`, the lookup table
    // the switch used, which had to agree with the manifest and was the only
    // thing saying so. Derived from the metrics above now.
    return { accountLabel: label, currency: null };
  },
});
