import { z } from "zod";
import type { Granularity, MetricId, ProviderManifest } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { googleHeaders, googleOAuth } from "../../google-oauth.ts";
import { bucketStart, dayAt, ymd } from "../../normalise.ts";
import type {
  AdapterContext,
  HttpResponse,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "youtube",
  name: "YouTube",
  // Not `analytics`: that bucket is product analytics, and a channel is a
  // distribution surface. It belongs beside Search Console, which is the
  // other "how are people finding me" connector.
  category: "marketing",
  tagline: "Views, watch time and subscribers for your channel.",
  docsUrl: "https://studio.youtube.com",
  dashboardUrl: "https://studio.youtube.com",
  iconPath: "/connectors/youtube.svg",
  accentColor: "#FF0000",
  keywords: ["yt", "channel", "video", "creator", "studio", "google"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your YouTube channel's analytics and estimated revenue"],
    // One Google account can own several channels, and a brand account's
    // channel is not the one the sign-in name suggests.
    requiresSelection: true,
    selectionLabel: "Which channel?",
  },
  fields: [],
  metrics: [
    {
      id: "views",
      label: "Views",
      shortLabel: "Views",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "YouTube Analytics `views` for the channel in the window. YouTube's day boundaries are Pacific Time, so a day here can straddle two of yours.",
    },
    {
      id: "watch_time",
      label: "Watch time",
      shortLabel: "Watch time",
      unit: "duration",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "YouTube Analytics `estimatedMinutesWatched` in the window, shown as hours. This is the figure monetisation thresholds are measured against.",
    },
    {
      id: "average_view_duration",
      label: "Average view duration",
      shortLabel: "Avg view",
      unit: "duration",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Watch time divided by views over the whole window — not the mean of the daily averages, which would weight a quiet day the same as a busy one.",
    },
    {
      id: "subscribers",
      label: "Subscribers",
      shortLabel: "Subs",
      unit: "count",
      granularities: ["day", "week", "month"],
      // A total, and YouTube publishes no history of it. The comparison is
      // real even so: the net change over the window comes from Analytics.
      supportsSeries: false,
      supportsCompare: true,
      methodology:
        "Subscribers on the channel right now, as the YouTube Data API reports it — which rounds anything over a thousand to three figures, so 12,345 reads as 12,300. The change against the previous window is the exact net gain from Analytics, so the arrow is right even where the total is rounded.",
    },
    {
      id: "new_subscribers",
      label: "New subscribers",
      shortLabel: "New subs",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      keywords: ["youtube", "subs gained", "audience"],
      methodology:
        "YouTube Analytics `subscribersGained`: people who subscribed in the window. Gross, not net — unsubscribes are not deducted, so this does not match the change in the subscriber total.",
    },
    {
      id: "likes",
      label: "Likes",
      shortLabel: "Likes",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "YouTube Analytics `likes` across the channel's videos in the window.",
    },
    {
      id: "comments",
      label: "Comments",
      shortLabel: "Comments",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "YouTube Analytics `comments` left on the channel's videos in the window.",
    },
    {
      id: "revenue",
      label: "Estimated revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      keywords: ["youtube", "earnings", "adsense", "payout"],
      methodology:
        "YouTube Analytics `estimatedRevenue`: net earnings from ads and YouTube Premium, after YouTube's share. Subject to month-end adjustment, so the current month is provisional, and it excludes partner-sold advertising. Only channels in the YouTube Partner Program have it at all.",
    },
    {
      id: "ad_revenue",
      label: "Ad revenue",
      shortLabel: "Ad rev.",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "YouTube Analytics `estimatedAdRevenue`: the advertising part of estimated revenue alone, with YouTube Premium earnings excluded. Also subject to month-end adjustment.",
    },
    {
      id: "rpm",
      label: "Revenue per mille",
      shortLabel: "RPM",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Estimated revenue per thousand views, computed over the whole window rather than averaged across daily rates. This is RPM as YouTube Studio reports it — total revenue over total views, every view counted — not CPM, which is per thousand ad impressions and counts only monetised playbacks.",
    },
  ],
  allowedHosts: [
    "youtubeanalytics.googleapis.com",
    // The Data API: naming the channel, listing them for the picker, and the
    // subscriber total, which Analytics does not report as a running count.
    "www.googleapis.com",
    "oauth2.googleapis.com",
  ],
  status: "beta",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  /**
   * Chosen from the picker after authorising.
   *
   * Charset-checked rather than matched against `UC…`: every channel id
   * today has that prefix, but the value only ever travels as a query
   * parameter, so the check that matters is that it carries nothing but
   * id characters.
   */
  channel_id: z.string().regex(/^[A-Za-z0-9_-]{6,64}$/, "That is not a YouTube channel ID."),
  // Written by the OAuth callback, never by a form.
  access_token: z.string().min(10),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.string().regex(/^\d+$/).optional(),
});
export type YouTubeCredentials = z.infer<typeof credentialSchema>;

const ANALYTICS = "https://youtubeanalytics.googleapis.com/v2";
const DATA = "https://www.googleapis.com/youtube/v3";

/** Analytics is a day or two behind, and the newest day is never final. */
const LAG_NOTE = "YouTube Analytics runs a day or two behind.";

/**
 * Every non-revenue metric comes out of one report, so the request is
 * identical for all of them and only the arithmetic at the end differs.
 *
 * `subscribersLost` is in here purely to net the subscriber total backwards;
 * it is not a metric of its own.
 */
const COLUMNS = [
  "views",
  "estimatedMinutesWatched",
  "likes",
  "comments",
  "subscribersGained",
  "subscribersLost",
] as const;

/**
 * The revenue columns, asked for only when a revenue metric is requested.
 *
 * Kept out of `COLUMNS` deliberately. A channel outside the YouTube Partner
 * Program answers 403 to any report naming a revenue column — not a report
 * with those columns blank — so folding them into the shared request would
 * take the view count down with them for every hobby channel on the service.
 */
const MONETARY_COLUMNS = ["estimatedRevenue", "estimatedAdRevenue"] as const;

/** Which of our metrics need `MONETARY_COLUMNS`, and so the monetary scope. */
const MONETARY_METRICS: ReadonlySet<MetricId> = new Set<MetricId>(["revenue", "ad_revenue", "rpm"]);

/**
 * The currencies `reports.query` will convert revenue into, from Google's
 * own list.
 *
 * Checked here rather than discovered by trying: an unsupported code is a
 * hard error on the whole report, which would take a working revenue widget
 * down for somebody whose account is simply priced in a currency YouTube
 * does not pay out in. Falling back to USD and saying so in the note is the
 * honest answer. A currency Google adds later reads as unsupported until
 * this list catches up, which is the safe direction to be wrong in.
 */
const CONVERTIBLE = new Set(
  (
    "AED ANG ARS AUD BDT BGN BHD BND BOB BRL BWP CAD CHF CLP CNY COP CRC CZK DKK DOP DZD EGP " +
    "EUR FJD GBP GTQ HKD HNL HRK HUF IDR ILS INR JMD JOD JPY KES KRW KWD KYD KZT LBP LKR MAD " +
    "MDL MKD MUR MVR MXN MYR NAD NGN NIO NOK NPR NZD OMR PEN PGK PHP PKR PLN PYG QAR RON RSD " +
    "RUB SAR SCR SEK SGD SLL SVC THB TND TRY TTD TWD TZS UAH UGX USD UYU UZS VEF VND XAF XOF " +
    "YER ZAR"
  ).split(" "),
);

/**
 * YouTube reports revenue as a decimal — `1234.56`, not `123456`.
 *
 * Every other connector here is handed minor units by its provider, so this
 * is the one place the conversion happens. Rounded rather than truncated:
 * a tile reading a cent low every day is a support thread about money being
 * wrong, and nobody can reproduce it.
 */
function toMinorUnits(amount: number): number {
  return Math.round(amount * 100);
}

/**
 * 403 from Google is the API not being enabled on the project, the account
 * not owning the channel, or the token having lost the scope. None is a rate
 * limit, all need a human, and the message names the first because that is
 * the one a fresh deployment hits.
 *
 * On a *revenue* report it means something else entirely and must not read as
 * a broken connection: YouTube answers 403 for any channel outside the
 * Partner Program, which is most channels. That is a metric this account
 * cannot have, not a credential to go and fix.
 */
function errorFor(host: string, response: HttpResponse, monetary = false): ProviderError {
  if (response.status === 403) {
    return monetary
      ? new ProviderError(
          "unsupported",
          "YouTube will not report revenue for this channel. It answers that for any channel outside the YouTube Partner Program, and for a connection authorised before this app asked for revenue — if the channel is monetised, reconnecting it will fix this.",
        )
      : new ProviderError(
          "auth_failed",
          "Google refused the request. Check the YouTube Data and YouTube Analytics APIs are enabled and this account owns the channel.",
        );
  }
  return errorForStatus(host, response);
}

interface ChannelEntry {
  id: string;
  snippet?: { title?: string; customUrl?: string };
  statistics?: { subscriberCount?: string };
}

interface ReportResponse {
  columnHeaders?: { name: string }[];
  rows?: (string | number)[][];
}

/** Totals of the raw report columns, so a rate or a mean can be taken over any span. */
interface Totals {
  views: number;
  minutesWatched: number;
  likes: number;
  comments: number;
  subscribersGained: number;
  subscribersLost: number;
  /**
   * Decimals, exactly as YouTube reports them, converted to minor units only
   * once a window has been summed — rounding each day to the cent first and
   * adding those up drifts from the true total by up to half a cent a day.
   * Zero on a non-monetary report, which never asks for them.
   */
  revenue: number;
  adRevenue: number;
}

function emptyTotals(): Totals {
  return {
    views: 0,
    minutesWatched: 0,
    likes: 0,
    comments: 0,
    subscribersGained: 0,
    subscribersLost: 0,
    revenue: 0,
    adRevenue: 0,
  };
}

/**
 * The channels the signed-in account owns.
 *
 * `fetch` rather than `ctx.http`, as in the other Google connectors: the
 * picker runs before any adapter context exists, against a host fixed here.
 */
async function listChannels(accessToken: string): Promise<ChannelEntry[]> {
  const response = await fetch(`${DATA}/channels?part=snippet,statistics&mine=true&maxResults=50`, {
    redirect: "manual",
    headers: googleHeaders(accessToken),
  });
  if (!response.ok) {
    throw new ProviderError(
      "auth_failed",
      "We could not list your YouTube channels. Check the YouTube Data API is enabled.",
    );
  }
  const body = (await response.json()) as { items?: ChannelEntry[] };
  return body.items ?? [];
}

/** One channel by id, through the adapter's allowlisted http. */
async function channel(
  ctx: AdapterContext,
  creds: YouTubeCredentials,
): Promise<ChannelEntry | null> {
  const response = await ctx.http(
    `${DATA}/channels?part=snippet,statistics&id=${encodeURIComponent(creds.channel_id)}`,
    { headers: googleHeaders(creds.access_token) },
  );
  if (!response.ok) throw errorFor("www.googleapis.com", response);
  const body = await response.json<{ items?: ChannelEntry[] }>();
  return body.items?.[0] ?? null;
}

/** A day-dimensioned report, plus the currency YouTube converted money into. */
interface Report {
  rows: { day: Date; totals: Totals }[];
  /** Null unless revenue was asked for. */
  currency: string | null;
}

/**
 * The currency to ask YouTube for, and whether it is the one the user wanted.
 *
 * YouTube converts at its own daily rates, which is why this is a request
 * parameter rather than something we do afterwards: converting a month of
 * revenue at today's rate is a different number from converting each day at
 * its own, and only one of those matches what Studio shows.
 */
function convertTo(preferred: string): { currency: string; substituted: boolean } {
  const want = preferred.toUpperCase();
  return CONVERTIBLE.has(want)
    ? { currency: want, substituted: false }
    : { currency: "USD", substituted: true };
}

/** One day-dimensioned report over `[from, to]`, as `{ day, …totals }` rows. */
async function report(
  ctx: AdapterContext,
  creds: YouTubeCredentials,
  from: Date,
  to: Date,
  monetary = false,
): Promise<Report> {
  const url = new URL(`${ANALYTICS}/reports`);
  // `channel==<id>` rather than `channel==MINE`: the connection is to one
  // channel, and an account that later gains a second must not have its
  // widgets silently start reporting whichever one YouTube considers
  // default.
  url.searchParams.set("ids", `channel==${creds.channel_id}`);
  url.searchParams.set("startDate", ymd(from, ctx.timeZone));
  url.searchParams.set("endDate", ymd(to, ctx.timeZone));
  const columns = monetary ? [...COLUMNS, ...MONETARY_COLUMNS] : [...COLUMNS];
  url.searchParams.set("metrics", columns.join(","));
  url.searchParams.set("dimensions", "day");
  url.searchParams.set("sort", "day");
  const money = monetary ? convertTo(ctx.preferredCurrency) : null;
  // Ignored by the API when no revenue column is requested, but sending it
  // anyway would put a currency on a report that has no money in it.
  if (money) url.searchParams.set("currency", money.currency);

  const response = await ctx.http(url.toString(), {
    headers: googleHeaders(creds.access_token),
  });
  if (!response.ok) throw errorFor("youtubeanalytics.googleapis.com", response, monetary);
  const body = await response.json<ReportResponse>();

  // Columns are read by name from `columnHeaders` rather than by the index
  // they were asked in. The API documents no ordering guarantee, and a
  // silently reordered response would put watch time in the likes tile —
  // wrong in a way no error surfaces.
  const headers = (body.columnHeaders ?? []).map((h) => h.name);
  const at = (name: string) => headers.indexOf(name);
  const index = {
    day: at("day"),
    views: at("views"),
    minutesWatched: at("estimatedMinutesWatched"),
    likes: at("likes"),
    comments: at("comments"),
    subscribersGained: at("subscribersGained"),
    subscribersLost: at("subscribersLost"),
    revenue: at("estimatedRevenue"),
    adRevenue: at("estimatedAdRevenue"),
  };
  if (index.day < 0) {
    throw new ProviderError("bad_response", "YouTube Analytics returned a report with no days.");
  }

  const number = (row: (string | number)[], position: number): number => {
    if (position < 0) return 0;
    const value = Number(row[position] ?? 0);
    return Number.isFinite(value) ? value : 0;
  };

  const rows = (body.rows ?? [])
    .map((row) => ({
      day: dayAt(String(row[index.day] ?? "")),
      totals: {
        views: number(row, index.views),
        minutesWatched: number(row, index.minutesWatched),
        likes: number(row, index.likes),
        comments: number(row, index.comments),
        subscribersGained: number(row, index.subscribersGained),
        subscribersLost: number(row, index.subscribersLost),
        revenue: number(row, index.revenue),
        adRevenue: number(row, index.adRevenue),
      },
    }))
    .filter((row) => !Number.isNaN(row.day.getTime()));

  return { rows, currency: money?.currency ?? null };
}

function add(into: Totals, from: Totals): void {
  into.views += from.views;
  into.minutesWatched += from.minutesWatched;
  into.likes += from.likes;
  into.comments += from.comments;
  into.subscribersGained += from.subscribersGained;
  into.subscribersLost += from.subscribersLost;
  into.revenue += from.revenue;
  into.adRevenue += from.adRevenue;
}

function sum(rows: { totals: Totals }[]): Totals {
  const totals = emptyTotals();
  for (const row of rows) add(totals, row.totals);
  return totals;
}

/** Minutes are what the API reports; seconds are what a `duration` is. */
const SECONDS_PER_MINUTE = 60;

function figure(metric: MetricId, totals: Totals): number {
  switch (metric) {
    case "views":
      return totals.views;
    case "watch_time":
      return totals.minutesWatched * SECONDS_PER_MINUTE;
    case "average_view_duration":
      return totals.views === 0 ? 0 : (totals.minutesWatched * SECONDS_PER_MINUTE) / totals.views;
    case "new_subscribers":
      return totals.subscribersGained;
    case "likes":
      return totals.likes;
    case "comments":
      return totals.comments;
    case "revenue":
      return toMinorUnits(totals.revenue);
    case "ad_revenue":
      return toMinorUnits(totals.adRevenue);
    case "rpm":
      // Per *thousand views*, and over the window's own totals — the mean of
      // daily RPMs would let a day with four views and one lucky ad outweigh
      // a day with forty thousand.
      return totals.views === 0 ? 0 : toMinorUnits((totals.revenue / totals.views) * 1000);
    default:
      return 0;
  }
}

const UNITS: Partial<Record<MetricId, RawSeries["unit"]>> = {
  views: "count",
  watch_time: "duration",
  average_view_duration: "duration",
  new_subscribers: "count",
  likes: "count",
  comments: "count",
  revenue: "currency",
  ad_revenue: "currency",
  rpm: "currency",
};

/** Everything the adapter can serve. `verify` narrows this per channel. */
const SERVED: MetricId[] = [
  "views",
  "watch_time",
  "average_view_duration",
  "subscribers",
  "new_subscribers",
  "likes",
  "comments",
  "revenue",
  "ad_revenue",
  "rpm",
];

export const youtube: ProviderAdapter<YouTubeCredentials> = {
  manifest,
  credentialSchema,
  // Empty, and explicit. Without it the connect page falls back to rendering
  // every schema field — which would put an access token in a text box.
  userInputFields: [],

  oauth: googleOAuth<YouTubeCredentials>({
    scopes: [
      // The channel list, its name and the subscriber total.
      "https://www.googleapis.com/auth/youtube.readonly",
      // Everything time-ranged. Separate scope, separate API.
      //
      // The *monetary* variant rather than plain `yt-analytics.readonly`,
      // which it is a superset of — Google's own wording is "monetary and
      // non-monetary". Asking for both would be asking twice for one thing.
      // It is what revenue needs, and a channel outside the Partner Program
      // can still grant it; it simply has no revenue behind it, which
      // `verify` discovers and narrows away rather than refusing.
      "https://www.googleapis.com/auth/yt-analytics-monetary.readonly",
    ],
    scopeSummary: ["Read your YouTube channel's analytics and estimated revenue"],
    empty: { channel_id: "" },
    selection: {
      label: "Which channel?",
      field: "channel_id",
      async options(credentials) {
        const channels = await listChannels(credentials.access_token);
        if (channels.length === 0) {
          // A Google account with no channel authorises perfectly happily
          // and then has nothing to report. Said here, where the user is
          // still in the flow, rather than as an empty picker.
          throw new ProviderError(
            "unsupported",
            "This Google account has no YouTube channel. Sign in with the account that owns the channel.",
          );
        }
        return channels.map((entry) => ({
          value: entry.id,
          label: entry.snippet?.title ?? entry.id,
          hint: entry.snippet?.customUrl,
        }));
      },
    },
  }),

  async verify(ctx, creds): Promise<VerifyResult> {
    // The channel rather than a report: it proves the token, the scope and
    // the Data API, and it is the call that names the connection. A channel
    // the account has lost access to answers with no items rather than a
    // 403, which is the case a report would not catch.
    const entry = await channel(ctx, creds);
    if (!entry) {
      throw new ProviderError(
        "auth_failed",
        "That YouTube channel is not on this Google account any more.",
      );
    }

    // One day of Analytics, to prove that API too. Both have to be enabled
    // on the Google project, and only one of them is enabled by connecting
    // Search Console or GA4 first — so a connection that verified on the
    // Data API alone would fail on its first metric instead.
    const today = ctx.now();
    await report(ctx, creds, today, today);

    // The same day again, asking for revenue, purely to find out whether
    // this channel has any. Most channels are not in the Partner Program
    // and answer 403; that is a smaller catalogue, not a failed connection,
    // so it narrows rather than throws. Telling a hobby creator their
    // perfectly good channel is broken would be the worse answer.
    let monetised = true;
    let currency: string | null = null;
    try {
      const probe = await report(ctx, creds, today, today, true);
      currency = probe.currency;
    } catch (error) {
      if (error instanceof ProviderError && error.code === "unsupported") {
        monetised = false;
        ctx.log("youtube channel has no revenue data", { channel: creds.channel_id });
      } else {
        throw error;
      }
    }

    return {
      accountLabel: entry.snippet?.title ?? creds.channel_id,
      currency,
      availableMetrics: monetised ? SERVED : SERVED.filter((m) => !MONETARY_METRICS.has(m)),
    };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    if (request.metric === "subscribers") return subscribers(ctx, creds, request);
    if (!UNITS[request.metric]) {
      throw new ProviderError("unsupported", `YouTube does not provide ${request.metric}.`);
    }
    return timeSeries(ctx, creds, request);
  },
};

/**
 * Anything that comes out of the day report.
 *
 * Rates and means are computed from the summed components per bucket, never
 * averaged from daily values — see `average_view_duration`.
 */
async function timeSeries(
  ctx: AdapterContext,
  creds: YouTubeCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const monetary = MONETARY_METRICS.has(request.metric);
  const windowMs = request.to.getTime() - request.from.getTime();
  const current = await report(ctx, creds, request.from, request.to, monetary);
  const previous = request.comparePrevious
    ? await report(
        ctx,
        creds,
        new Date(request.from.getTime() - windowMs),
        new Date(request.from.getTime() - 1),
        monetary,
      )
    : null;

  return {
    unit: UNITS[request.metric] ?? "count",
    currency: current.currency,
    points: bucket(current.rows, request.metric, request.granularity, request, ctx.timeZone),
    value: figure(request.metric, sum(current.rows)),
    previousValue: previous ? figure(request.metric, sum(previous.rows)) : null,
    note: note(ctx, monetary, current.currency),
  };
}

/**
 * What the tile says under the number.
 *
 * The substitution is worth a sentence rather than a silent conversion: a
 * figure in dollars under a heading that says the account is in rupees is
 * the kind of wrong a user only catches by doing the arithmetic themselves.
 */
function note(ctx: AdapterContext, monetary: boolean, currency: string | null): string {
  if (!monetary) return LAG_NOTE;
  const substituted = currency !== null && currency !== ctx.preferredCurrency.toUpperCase();
  return [
    LAG_NOTE,
    "Revenue is provisional until YouTube's month-end adjustment.",
    substituted
      ? `YouTube cannot report in ${ctx.preferredCurrency.toUpperCase()}, so this is ${currency}.`
      : null,
  ]
    .filter(Boolean)
    .join(" ");
}

/**
 * The subscriber total, with the window's net change behind it.
 *
 * Two calls, because neither API has both halves: the Data API has the
 * current count and no history, Analytics has the daily deltas and no
 * running total. Walking the deltas back from today is what makes the
 * comparison exact even though the total is rounded.
 */
async function subscribers(
  ctx: AdapterContext,
  creds: YouTubeCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const entry = await channel(ctx, creds);
  const count = Number(entry?.statistics?.subscriberCount ?? NaN);
  if (!Number.isFinite(count)) {
    // A channel can hide its subscriber count, and then the field is simply
    // absent. Zero would read as a channel nobody follows.
    throw new ProviderError(
      "unsupported",
      "This channel does not publish its subscriber count. Try new subscribers instead.",
    );
  }

  let net: number | null = null;
  if (request.comparePrevious) {
    const { rows } = await report(ctx, creds, request.from, request.to);
    const totals = sum(rows);
    net = totals.subscribersGained - totals.subscribersLost;
  }

  return {
    unit: "count",
    currency: null,
    // One point, at now. A flat line invented from a single reading would
    // look like data.
    points: [{ t: ctx.now(), v: count }],
    value: count,
    previousValue: net === null ? null : count - net,
    asOf: ctx.now(),
    note: "YouTube rounds subscriber counts over a thousand to three figures.",
  };
}

/** Gap-filled like `bucketSum`, but each bucket carries components rather than one sum. */
function bucket(
  rows: { day: Date; totals: Totals }[],
  metric: MetricId,
  granularity: Granularity,
  window: { from: Date; to: Date },
  timeZone: string,
): { t: Date; v: number }[] {
  const byBucket = new Map<number, Totals>();
  for (const row of rows) {
    const key = bucketStart(row.day, granularity, timeZone).getTime();
    const totals = byBucket.get(key) ?? emptyTotals();
    add(totals, row.totals);
    byBucket.set(key, totals);
  }

  const points: { t: Date; v: number }[] = [];
  let cursor = bucketStart(window.from, granularity, timeZone);
  const end = bucketStart(window.to, granularity, timeZone);
  for (let i = 0; cursor <= end && i < 1000; i++) {
    const totals = byBucket.get(cursor.getTime());
    points.push({ t: new Date(cursor), v: totals ? figure(metric, totals) : 0 });
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
