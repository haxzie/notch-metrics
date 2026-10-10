import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { bucketSum, dayAt, ymd } from "../../normalise.ts";
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
  api_key: z.string().min(8),
  secret_key: z.string().min(8),
  region: z.enum(["us", "eu"]).default("us"),
});
export type AmplitudeCredentials = z.infer<typeof credentialSchema>;

function host(creds: AmplitudeCredentials): string {
  return creds.region === "eu" ? "analytics.eu.amplitude.com" : "amplitude.com";
}

/**
 * The Dashboard API is signed with the key pair as HTTP Basic, not with a
 * bearer token — the secret key is the password.
 *
 * `btoa` rather than a Buffer: this runs in a Worker. Both keys are hex, so
 * there is nothing outside Latin-1 for it to choke on.
 */
function authorization(creds: AmplitudeCredentials): string {
  return `Basic ${btoa(`${creds.api_key}:${creds.secret_key}`)}`;
}

/**
 * A response from either Dashboard chart endpoint.
 *
 * The two label their groups differently — `seriesLabels` for segmentation,
 * `seriesMeta` for users — and neither matters here: one unsegmented query
 * has exactly one group, so the series is always `series[0]`.
 */
interface ChartResponse {
  data?: {
    series?: (number | null)[][];
    xValues?: string[];
    /**
     * Per group, the figure for the window as a whole rather than per day.
     *
     * The only way to get a de-duplicated user count over a multi-day
     * window out of this API: summing the daily uniques counts a person once
     * per day they showed up.
     */
    seriesCollapsed?: { value?: number | null }[][];
  };
}

async function get(
  ctx: AdapterContext,
  creds: AmplitudeCredentials,
  path: string,
  params: Record<string, string>,
): Promise<ChartResponse> {
  const url = new URL(`https://${host(creds)}${path}`);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);

  const response = await ctx.http(url.toString(), {
    headers: { authorization: authorization(creds), accept: "application/json" },
  });
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new ProviderError(
        "auth_failed",
        `Amplitude rejected these keys. Check they are the ${creds.region.toUpperCase()} project's pair — the other region answers ${response.status} too.`,
      );
    }
    throw errorForStatus(host(creds), response);
  }
  return response.json<ChartResponse>();
}

/** How a metric is asked for, and whether its bars add up to its headline. */
interface Spec {
  path: string;
  params: Record<string, string>;
  /**
   * False when the window total is a de-duplicated count of people rather
   * than a sum over days — then the headline comes from `seriesCollapsed`
   * and not from the series.
   */
  additive: boolean;
}

const SPECS: Partial<Record<MetricId, Spec>> = {
  // `_all` and `_active` are Amplitude's own pseudo-events for "Any Event"
  // and "Any Active Event"; without them this would need every event name in
  // the project listed by hand.
  events: {
    path: "/api/2/events/segmentation",
    params: { e: JSON.stringify({ event_type: "_all" }), m: "totals" },
    additive: true,
  },
  active_users: {
    path: "/api/2/events/segmentation",
    params: { e: JSON.stringify({ event_type: "_active" }), m: "uniques" },
    additive: false,
  },
  // The users endpoint rather than a segmentation query: "first ever event"
  // is not expressible as an event filter, and `m=new` is the same figure
  // Amplitude's own New Users chart shows.
  new_users: { path: "/api/2/users", params: { m: "new" }, additive: true },
};

function toNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/** One chart call: the daily rows, plus the window figure when the API gives one. */
async function chart(
  ctx: AdapterContext,
  creds: AmplitudeCredentials,
  spec: Spec,
  from: Date,
  to: Date,
): Promise<{ rows: { at: Date; amount: number }[]; collapsed: number | null }> {
  const body = await get(ctx, creds, spec.path, {
    ...spec.params,
    // Both ends inclusive, as whole days in the project's timezone.
    start: ymd(from, ctx.timeZone).replace(/-/g, ""),
    end: ymd(to, ctx.timeZone).replace(/-/g, ""),
    // Daily, always, and rolled up to weeks and months locally. Amplitude's
    // own `i=7` buckets start on a Sunday while every other series in the
    // notch starts its week on a Monday, and two chart tiles disagreeing
    // about where a week begins is worse than one extra sum here.
    i: "1",
  });

  const series = body.data?.series?.[0] ?? [];
  const xValues = body.data?.xValues ?? [];
  const rows = xValues.map((label, index) => ({
    // Noon UTC of the labelled day, so the row lands on that calendar day in
    // any zone within ±11 hours.
    at: dayAt(label),
    amount: toNumber(series[index]),
  }));

  const collapsed = body.data?.seriesCollapsed?.[0]?.[0]?.value;
  return {
    rows: rows.filter((row) => !Number.isNaN(row.at.getTime())),
    collapsed: typeof collapsed === "number" && Number.isFinite(collapsed) ? collapsed : null,
  };
}

/** The headline for one window: Amplitude's own total, or the sum of the days. */
function headline(
  spec: Spec,
  result: { rows: { at: Date; amount: number }[]; collapsed: number | null },
): number {
  if (!spec.additive && result.collapsed !== null) return result.collapsed;
  return result.rows.reduce((total, row) => total + row.amount, 0);
}

export const amplitude: ProviderAdapter<AmplitudeCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    // A one-day active-users query. There is no identity endpoint on the
    // Dashboard API — no "who am I", no project name — so the cheapest
    // thing that proves the pair works is the smallest real query.
    const today = ymd(ctx.now(), ctx.timeZone).replace(/-/g, "");
    await get(ctx, creds, "/api/2/users", { start: today, end: today, m: "active", i: "1" });

    return {
      // Amplitude never names the project over this API, so there is nothing
      // to distinguish two connections by but the key. Half of it, since the
      // API key is not the secret but is still not ours to print in full.
      accountLabel: `project ${creds.api_key.slice(0, 6)}…`,
      currency: null,
      availableMetrics: Object.keys(SPECS) as MetricId[],
    };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    const spec = SPECS[request.metric];
    if (!spec) {
      throw new ProviderError("unsupported", `Amplitude does not provide ${request.metric}.`);
    }

    const current = await chart(ctx, creds, spec, request.from, request.to);

    const windowMs = request.to.getTime() - request.from.getTime();
    const previous = request.comparePrevious
      ? await chart(
          ctx,
          creds,
          spec,
          new Date(request.from.getTime() - windowMs),
          // A millisecond before `from`, so the two windows do not both
          // claim the boundary day.
          new Date(request.from.getTime() - 1),
        )
      : null;

    return {
      unit: "count",
      currency: null,
      points: request.wantSeries
        ? bucketSum(current.rows, {
            from: request.from,
            to: request.to,
            granularity: request.granularity,
            timeZone: ctx.timeZone,
          })
        : [],
      value: headline(spec, current),
      previousValue: previous ? headline(spec, previous) : null,
    };
  },
};
