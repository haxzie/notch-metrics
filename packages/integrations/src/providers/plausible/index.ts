import { z } from "zod";
import type { Granularity, MetricId } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import { metricsFor, provider, type SeriesResult } from "../../metric.ts";
import { bucketSum, instantOfWallClock } from "../../normalise.ts";
import type { AdapterContext, HttpResponse, MetricRequest } from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

export { manifest };

/**
 * Days are the *site's* reporting timezone, not the user's.
 *
 * Repeated in every methodology rather than said once, because it is the
 * answer to "why is this 40 and the dashboard says 41" and nobody reads the
 * tooltip of the metric next door.
 */
const ZONE_NOTE =
  "Buckets are your Plausible site's reporting timezone, so the figures match its own dashboard.";

const HOST = "plausible.io";

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  // Trimmed and lower-cased: Plausible matches the domain exactly, and a
  // pasted "Example.com " is a 404 that reads as a missing site.
  site_id: z
    .string()
    .min(1)
    .transform((value) => value.trim().toLowerCase()),
});
export type PlausibleCredentials = z.infer<typeof credentialSchema>;

const { series } = metricsFor<PlausibleCredentials>();

async function request<T>(
  ctx: AdapterContext,
  creds: PlausibleCredentials,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await ctx.http(`https://${HOST}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${creds.api_key}`,
      accept: "application/json",
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...init.headers,
    },
  });
  if (!response.ok) throw await failure(response);
  return response.json<T>();
}

/**
 * Plausible puts its own sentence in the body, and it is a better one than
 * ours.
 *
 * "Site could not be found" and "metric is not available on your plan" both
 * arrive as a 4xx that `errorForStatus` can only call a bad response, which
 * sends somebody to re-roll a key that was never the problem.
 */
async function failure(response: HttpResponse): Promise<ProviderError> {
  if (response.status === 400 || response.status === 404) {
    const body = await response.json<{ error?: string }>().catch(() => ({}) as { error?: string });
    const detail = body.error?.trim();
    // Classified on the status, not on whether a body turned up. A 404 from
    // either of these paths is always "this key cannot see that site", and a
    // connector that only says so when Plausible bothers to explain is a
    // connector that says the wrong thing at the worst moment.
    return new ProviderError(
      response.status === 404 ? "unsupported" : "bad_response",
      detail ? `Plausible: ${detail}` : `Plausible returned ${response.status}`,
    );
  }
  return errorForResponse(HOST, response);
}

interface QueryResult {
  results?: { metrics?: (number | null)[]; dimensions?: string[] }[];
}

/**
 * One Stats API query.
 *
 * `date_range` is sent as a pair of instants rather than one of Plausible's
 * shorthands ("7d", "month"): the window comes from the widget and the
 * shorthands are relative to Plausible's own idea of today.
 */
async function query(
  ctx: AdapterContext,
  creds: PlausibleCredentials,
  options: { metric: string; from: Date; to: Date; dimension?: string },
): Promise<{ metrics?: (number | null)[]; dimensions?: string[] }[]> {
  const body = await request<QueryResult>(ctx, creds, "/api/v2/query", {
    method: "POST",
    body: JSON.stringify({
      site_id: creds.site_id,
      metrics: [options.metric],
      date_range: [options.from.toISOString(), options.to.toISOString()],
      ...(options.dimension ? { dimensions: [options.dimension] } : {}),
    }),
  });
  return body.results ?? [];
}

/** The time dimension whose buckets are the ones the widget asked for. */
function dimensionFor(granularity: Granularity): string {
  return `time:${granularity}`;
}

/**
 * Plausible labels a bucket `2026-10-05` or `2026-10-05 14:00:00`, with no
 * offset, in the site's reporting timezone.
 *
 * Read as the user's wall clock rather than as UTC. The two zones agree for
 * almost everybody — Plausible is configured once, to where you are — and
 * when they do not, this only shifts where a bar sits, never what it counts.
 */
function instantOf(label: string, timeZone: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?/.exec(label);
  if (!match) {
    throw new ProviderError("bad_response", `Plausible returned an unreadable bucket: ${label}`);
  }
  const [, year, month, day, hour, minute] = match;
  return instantOfWallClock(
    {
      year: Number(year),
      month: Number(month),
      day: Number(day),
      hour: Number(hour ?? "0"),
      minute: Number(minute ?? "0"),
    },
    timeZone,
  );
}

function toNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * One Plausible metric, which is four metrics minus a name and a scale.
 *
 * All four ask the same two or three questions and differ only in what
 * Plausible calls the metric and whether its number needs dividing. As a
 * single `case` that handled all four, that sameness was carried by two side
 * tables — a `METRICS` lookup and a `scale()` keyed on metric id — each of
 * which had to agree with the manifest and with the other. Here it is one
 * function, and what differs is its arguments.
 */
function statsMetric(options: {
  id: MetricId;
  /** What Plausible calls it. It says "visits" where everything else says sessions. */
  apiMetric: string;
  label: string;
  shortLabel: string;
  unit: "count" | "ratio";
  granularities: [Granularity, ...Granularity[]];
  methodology: string;
  /** Plausible reports `bounce_rate` as a percentage; a `ratio` is a fraction. */
  scale?: (value: number) => number;
}) {
  const scale = options.scale ?? ((value: number) => value);

  /** The single figure for a window, from a query with no time dimension. */
  const total = async (
    ctx: AdapterContext,
    creds: PlausibleCredentials,
    from: Date,
    to: Date,
  ): Promise<number> => {
    const rows = await query(ctx, creds, { metric: options.apiMetric, from, to });
    return scale(toNumber(rows[0]?.metrics?.[0]));
  };

  return series({
    id: options.id,
    label: options.label,
    shortLabel: options.shortLabel,
    unit: options.unit,
    granularities: options.granularities,
    compare: true,
    methodology: options.methodology,

    async fetch(ctx, creds, request: MetricRequest): Promise<SeriesResult> {
      // Asked for separately rather than summed off the chart, for both of the
      // metrics where those differ: a visitor active on three days is one
      // unique visitor, and a bounce rate is a ratio, not an addend. Plausible
      // also warns that `visitors` and `visits` may come from different tables
      // depending on the query, so its own aggregate is the figure that
      // matches its own dashboard.
      const value = await total(ctx, creds, request.from, request.to);
      const windowMs = request.to.getTime() - request.from.getTime();
      const previousValue = request.comparePrevious
        ? await total(ctx, creds, new Date(request.from.getTime() - windowMs), request.from)
        : null;

      // One row per bucket, bucketed by Plausible itself at the granularity
      // asked for — so a week is weighted by its own sessions rather than
      // being the mean of seven daily rates, which is what rolling days up
      // here would produce. `bucketSum` is then only gap-filling: it sees one
      // row per bucket, so nothing is added to anything.
      let points: { t: Date; v: number }[] = [];
      if (request.wantSeries) {
        const rows = await query(ctx, creds, {
          metric: options.apiMetric,
          from: request.from,
          to: request.to,
          dimension: dimensionFor(request.granularity),
        });
        points = bucketSum(
          rows.map((row) => ({
            at: instantOf(row.dimensions?.[0] ?? "", ctx.timeZone),
            amount: scale(toNumber(row.metrics?.[0])),
          })),
          {
            from: request.from,
            to: request.to,
            granularity: request.granularity,
            timeZone: ctx.timeZone,
          },
        );
      }

      return { points, value, previousValue };
    },
  });
}

export const visitors = statsMetric({
  id: "visitors",
  apiMetric: "visitors",
  label: "Unique visitors",
  shortLabel: "Visitors",
  unit: "count",
  granularities: ["hour", "day", "week", "month"],
  methodology: `Distinct visitors in the window. The headline counts each visitor once across the whole window, so the bars do not add up to it. ${ZONE_NOTE}`,
});

export const pageviews = statsMetric({
  id: "pageviews",
  apiMetric: "pageviews",
  label: "Pageviews",
  shortLabel: "Views",
  unit: "count",
  granularities: ["hour", "day", "week", "month"],
  methodology: `Total pages viewed in the window, with repeat views by one visitor all counted. ${ZONE_NOTE}`,
});

export const bounceRate = statsMetric({
  id: "bounce_rate",
  apiMetric: "bounce_rate",
  label: "Bounce rate",
  shortLabel: "Bounce",
  unit: "ratio",
  granularities: ["day", "week", "month"],
  scale: (value) => value / 100,
  methodology: `Share of sessions that left after one interaction. Plausible computes each bar over its own bucket, so a week is weighted by its sessions rather than being the mean of seven daily rates. ${ZONE_NOTE}`,
});

export const sessions = statsMetric({
  id: "sessions",
  // Plausible says "visits"; every other connector here says sessions.
  apiMetric: "visits",
  label: "Sessions",
  shortLabel: "Sessions",
  unit: "count",
  granularities: ["hour", "day", "week", "month"],
  methodology: `Visits started in the window, which Plausible calls "visits". A session that spans midnight is counted in the bucket it started in. ${ZONE_NOTE}`,
});

export const plausible = provider({
  manifest,
  credentialSchema,
  // Declaration order is the catalogue's order, and now also the order
  // `availableMetrics` reports.
  metrics: [visitors, pageviews, bounceRate, sessions],

  async verify(ctx, creds) {
    // The site endpoint rather than a stats query: it proves the key, proves
    // this site is on the key's team, and costs nothing in stats quota. A
    // Stats API key can read it on any plan that includes the Stats API.
    const site = await request<{ domain?: string; timezone?: string }>(
      ctx,
      creds,
      `/api/v1/sites/${encodeURIComponent(creds.site_id)}`,
    ).catch((error: unknown) => {
      if (error instanceof ProviderError && error.code === "unsupported") {
        throw new ProviderError(
          "auth_failed",
          `Plausible has no site "${creds.site_id}" on this key's team. A key is scoped to one team, and a site owned by another answers the same way a wrong domain does.`,
        );
      }
      throw error;
    });

    // No `availableMetrics`: it was `Object.keys(METRICS)`, a side table
    // that had to agree with the manifest and silently did not — it listed
    // sessions before bounce rate where the manifest has them the other way
    // round. Derived from the metrics below now, so there is one order.
    return { accountLabel: site.domain?.trim() || creds.site_id, currency: null };
  },
});
