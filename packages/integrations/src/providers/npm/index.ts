import { z } from "zod";
import type { AuthField } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import { metricsFor, provider, type ScalarResult, type SeriesResult } from "../../metric.ts";
import { bucketSum, ymd } from "../../normalise.ts";
import type { AdapterContext, HttpResponse, MetricRequest } from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

export { manifest };

/** Download counts. Public, and takes no credential at all. */
const STATS = "https://api.npmjs.org";

/**
 * Empty, and that is the whole point.
 *
 * npm publishes download counts to anyone who asks. This asked for an access
 * token at first, purely so `verify` could call `/-/whoami` and name the
 * connection — which turned out to cost a trip through npm's 2FA for a label.
 * A credential with no use is one that can leak for no reason.
 */
export const credentialSchema = z.object({});
export type NpmCredentials = z.infer<typeof credentialSchema>;

const { scalar, series } = metricsFor<NpmCredentials>();

/**
 * The package a tile counts, asked for when the widget is configured.
 *
 * On the widget rather than the connection, like GitHub's repository: one
 * token covers everything the account can see, and a tile per package is the
 * normal case. It also means the downloads of a package you do not own cost
 * no second connection.
 *
 * The pattern is npm's own name rule — lower case, optionally scoped — and it
 * is checked again in `packageFor` because this one is only a hint the app
 * renders.
 */
const PACKAGE_PARAM: AuthField = {
  key: "package",
  label: "Package",
  type: "string",
  required: true,
  placeholder: "react or @scope/name",
  help: "Which package this tile counts.",
  pattern: "^(@[a-z0-9-~][a-z0-9-._~]*/)?[a-z0-9-~][a-z0-9-._~]*$",
};

/**
 * npm counts a download against a **UTC** day and publishes nothing else.
 *
 * Said in every methodology rather than once, because it is the answer to
 * "why is this 40 and npm says 41" and nobody reads the tooltip of the metric
 * next door.
 */
const UTC_NOTE = "Days are npm's own UTC days, so the figures match npmjs.com.";

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Which package this request is about.
 *
 * Re-validated here rather than trusted from the manifest's `pattern`: that
 * is a hint the app renders, and this value reaches a request path. A scoped
 * name carries a slash, which is exactly the character that would otherwise
 * address a different endpoint on an allowed host.
 */
function packageFor(request: MetricRequest): string {
  const name = (request.params.package ?? "").trim().toLowerCase();
  if (!name) throw new ProviderError("unsupported", "Pick a package for this widget.");
  if (!new RegExp(PACKAGE_PARAM.pattern ?? "").test(name)) {
    throw new ProviderError("unsupported", `"${name}" is not an npm package name.`);
  }
  return name;
}

/** Each segment encoded separately, so a scope's slash survives as a slash. */
function encodePackage(name: string): string {
  return name
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

async function stats<T>(ctx: AdapterContext, path: string): Promise<T> {
  const response = await ctx.http(`${STATS}${path}`, { headers: { accept: "application/json" } });
  if (!response.ok) throw await failure(response, "npm's download statistics");
  return response.json<T>();
}

async function failure(response: HttpResponse, subject: string): Promise<ProviderError> {
  if (response.status === 404) {
    // A package that does not exist and one that was unpublished answer the
    // same 404, and so does a private package this token cannot see. The
    // message has to cover all three because the status cannot tell them
    // apart — and none of them is a reason to mark the connection broken.
    return new ProviderError(
      "unsupported",
      "That package could not be read. Check the name, and that this token can see it.",
    );
  }
  return errorForResponse(subject, response);
}

interface RangeResponse {
  start: string;
  end: string;
  package: string;
  downloads: { downloads: number; day: string }[];
}

interface PointResponse {
  downloads: number;
  start: string;
  end: string;
  package: string;
}

/**
 * Daily counts over the window, rolled up to whatever the chart asked for.
 *
 * npm publishes days and only days, so a week or a month bucket is summed
 * here. `bucketSum` is the roll-up rather than a second bucketing: one row
 * per day in, one bucket per period out.
 */
async function downloadsSeries(
  ctx: AdapterContext,
  _creds: NpmCredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  const name = packageFor(request);

  const current = await downloadDays(ctx, name, request.from, request.to);
  const events = current.map((row) => ({
    // Midday UTC rather than midnight. The day is a UTC day whatever zone the
    // reader is in, and midnight parsed into a zone behind UTC lands on the
    // day before — which silently shifts every bar by one.
    at: new Date(`${row.day}T12:00:00Z`),
    amount: row.downloads,
  }));

  const points = bucketSum(events, {
    from: request.from,
    to: request.to,
    granularity: request.granularity,
    timeZone: ctx.timeZone,
  });

  // Summed from the rows, not the buckets: a bucket is a whole period and the
  // window's edges are instants, so a headline taken off the buckets would
  // count days the window does not cover.
  const value = events.reduce((total, row) => total + row.amount, 0);

  const notes: string[] = [];
  const missing = unaggregated(current);
  if (missing > 0) {
    notes.push(
      `${missing} of ${current.length} days have not been aggregated by npm yet and read as zero.`,
    );
  }

  let previousValue: number | undefined;
  if (request.comparePrevious) {
    const span = request.to.getTime() - request.from.getTime();
    const previousTo = new Date(request.from.getTime() - 1);
    const previousFrom = new Date(previousTo.getTime() - span);
    const previous = await downloadDays(ctx, name, previousFrom, previousTo);

    // Only when the two windows are aggregated to about the same depth.
    // npm backfills days late and scattered — September had gaps on the 7th,
    // 8th and 15th — so a window with three missing days compared against one
    // with none reports npm's own backlog as a fall in downloads.
    // A tenth of the window, and at least a day. A couple of missing days
    // either side is noise; a quarter of the window missing on one side is a
    // comparison that would mostly measure npm's backlog.
    const tolerance = Math.max(1, Math.round(current.length / 10));
    const previousGaps = interiorGaps(previous);
    const gaps = interiorGaps(current);
    if (Math.abs(previousGaps - gaps) <= tolerance) {
      previousValue = previous.reduce((total, row) => total + row.downloads, 0);
    } else {
      notes.push(
        `No comparison: npm has left ${gaps} days uncounted inside this window and ` +
          `${previousGaps} inside the one before, so a change between them would mostly ` +
          `measure npm's backlog.`,
      );
    }
  }

  return {
    value,
    previousValue,
    points: request.wantSeries ? points : [],
    note: notes.length > 0 ? notes.join(" ") : undefined,
  };
}

/** Days npm has not finished counting, which it reports as a zero. */
function unaggregated(days: { downloads: number }[]): number {
  return days.filter((day) => day.downloads === 0).length;
}

/**
 * Gaps with an aggregated day after them.
 *
 * npm lags a day or two at the end of every window, and a window ending today
 * therefore always has trailing zeros where the one before it has none.
 * Counting those made the two windows look incomparable every single time,
 * so the delta was withheld on every poll. What actually makes a comparison
 * meaningless is npm failing to backfill days *inside* the window — react had
 * six of those in one month, scattered across two separate runs.
 */
function interiorGaps(days: { downloads: number }[]): number {
  const lastCounted = days.findLastIndex((day) => day.downloads > 0);
  if (lastCounted < 0) return 0;
  return unaggregated(days.slice(0, lastCounted));
}

async function downloadDays(
  ctx: AdapterContext,
  name: string,
  from: Date,
  to: Date,
): Promise<RangeResponse["downloads"]> {
  const body = await stats<RangeResponse>(
    ctx,
    `/downloads/range/${ymd(from, "UTC")}:${ymd(to, "UTC")}/${encodePackage(name)}`,
  );
  return body.downloads;
}

/**
 * npm's own "Weekly Downloads": a trailing seven-day sum, one point per day.
 *
 * Not calendar weeks. npmjs.com's figure for react on 4 November was
 * 248,185,175, and that is exactly the sum of the seven days ending that
 * day — `/downloads/point/last-week` returns the same number. Plotting
 * discrete Monday-to-Sunday bars instead gave 116M, 126M, 243M on
 * consecutive weeks, which is both the wrong shape and wildly unstable:
 * npm's counts service had no data at all for 13–15 and 19–21 October, the
 * same days for every package, so a calendar week holding three of them came
 * out half empty.
 *
 * A rolling window spreads those gaps across seven points instead of
 * crushing one bar, which is why npm's own chart looks smooth through the
 * same outage.
 */
async function weeklyDownloads(
  ctx: AdapterContext,
  _creds: NpmCredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  const name = packageFor(request);
  const span = request.to.getTime() - request.from.getTime();

  // Six days of lead-in so the first point has a whole week behind it, and a
  // further window's worth when a comparison is wanted.
  const lead = 6 * DAY_MS;
  const earliest = new Date(request.from.getTime() - lead - (request.comparePrevious ? span : 0));
  const days = await downloadDays(ctx, name, earliest, request.to);

  // Trailing days npm has not counted yet are dropped rather than summed as
  // zero. Kept, they drag the last points down — react's rolling total fell
  // from 248M to 171M across two uncounted days — and npm's own page does
  // not show that dip because it ends at the last complete day.
  let end = days.length;
  while (end > 0 && (days[end - 1]?.downloads ?? 0) === 0) end -= 1;
  const counted = days.slice(0, end);

  const rolling: { t: Date; v: number }[] = [];
  for (let i = 6; i < counted.length; i++) {
    let total = 0;
    for (let j = i - 6; j <= i; j++) total += counted[j]?.downloads ?? 0;
    const label = counted[i]?.day;
    if (label) rolling.push({ t: new Date(`${label}T12:00:00Z`), v: total });
  }

  const inWindow = rolling.filter((point) => point.t >= request.from);
  const latest = inWindow.at(-1) ?? rolling.at(-1);

  // The figure a window earlier, which is what the delta is against — not a
  // sum over the window, because this metric is a snapshot at every point.
  const previousAt = latest ? latest.t.getTime() - span : 0;
  const previous = request.comparePrevious
    ? rolling.filter((point) => point.t.getTime() <= previousAt).at(-1)
    : undefined;

  const skipped = unaggregated(counted);
  return {
    value: latest?.v ?? 0,
    previousValue: previous?.v,
    points: request.wantSeries ? inWindow : [],
    note:
      skipped > 0
        ? `${skipped} days inside this window were never counted by npm, so the line dips through them.`
        : undefined,
  };
}

export const downloads = series({
  id: "downloads",
  label: "Downloads",
  shortLabel: "Downloads",
  unit: "count",
  compare: true,
  // No `hour`: npm publishes a day at a time and nothing finer, so an hourly
  // bucket would be a chart of one filled bar in twenty-four.
  granularities: ["day", "week", "month"],
  params: [PACKAGE_PARAM],
  freshnessSeconds: 900,
  methodology: `Downloads of this package in the window, as npm counts them. Includes CI and mirrors, which is what npmjs.com shows too. Days npm has not finished aggregating come back as zero and are named in the note rather than hidden. ${UTC_NOTE}`,
  fetch: downloadsSeries,
});

export const weekly = series({
  id: "weekly_downloads",
  label: "Weekly downloads",
  shortLabel: "Weekly",
  unit: "count",
  compare: true,
  // Daily points, each a trailing week. A "week" granularity here would mean
  // calendar weeks, which is the thing this metric exists not to be.
  granularities: ["day"],
  params: [PACKAGE_PARAM],
  freshnessSeconds: 900,
  methodology: `npm's own weekly downloads: the seven days ending on each point, which is the figure and the line npmjs.com shows. The headline is the most recent complete week, so it matches the package page exactly. ${UTC_NOTE}`,
  fetch: weeklyDownloads,
});

export const npm = provider({
  manifest,
  credentialSchema,
  metrics: [downloads, weekly],

  // Nothing to prove. There is no credential, and no package either — that
  // is a widget's parameter — so there is nothing a connect-time check could
  // ask npm about. A widget pointed at a package that does not exist says so
  // on the tile, which is where the package was named.
  async verify() {
    return { accountLabel: "npm", currency: null };
  },
});
