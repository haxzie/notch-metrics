import { afterEach, describe, expect, it, vi } from "vitest";
import { youtube } from "../src/providers/youtube/index.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { channel_id: "UCabcdefghijklmnopqrstuv", access_token: "ya29.0123456789" };

const request = {
  metric: "views" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-04T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

/**
 * Columns deliberately in a different order from the request, because the
 * adapter reads them by name — see the comment in `report`.
 */
const COLUMN_HEADERS = [
  { name: "day" },
  { name: "subscribersGained" },
  { name: "views" },
  { name: "subscribersLost" },
  { name: "comments" },
  { name: "estimatedMinutesWatched" },
  { name: "likes" },
];

function day(
  date: string,
  values: {
    views: number;
    minutes: number;
    likes?: number;
    comments?: number;
    gained?: number;
    lost?: number;
  },
) {
  return [
    date,
    values.gained ?? 0,
    values.views,
    values.lost ?? 0,
    values.comments ?? 0,
    values.minutes,
    values.likes ?? 0,
  ];
}

const rows = [
  day("2026-10-01", { views: 100, minutes: 200, likes: 7, comments: 2, gained: 10, lost: 1 }),
  day("2026-10-02", { views: 300, minutes: 150, likes: 1, comments: 0, gained: 5, lost: 9 }),
  // A busy day at a much shorter average, so a mean of the daily means would
  // differ from the window's own.
  day("2026-10-03", { views: 600, minutes: 100, likes: 0, comments: 4, gained: 0, lost: 0 }),
];

const REPORT = { columnHeaders: COLUMN_HEADERS, rows };

function channelBody(statistics: Record<string, string> | null = { subscriberCount: "12300" }) {
  return {
    items: [
      {
        id: creds.channel_id,
        snippet: { title: "Notch Metrics", customUrl: "@notchmetrics" },
        ...(statistics ? { statistics } : {}),
      },
    ],
  };
}

function stubChannels(items: unknown[]) {
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ items })));
}

/**
 * A separate fixture from `rows`, with money on it.
 *
 * The daily figures are deliberately awkward — 1.111, 2.222, 3.333 — so that
 * rounding each day to the cent (666) and rounding the summed window (667)
 * give different answers, and a test can tell which one happened.
 */
const MONEY_COLUMN_HEADERS = [
  ...COLUMN_HEADERS,
  { name: "estimatedRevenue" },
  { name: "estimatedAdRevenue" },
];

function moneyDay(date: string, views: number, revenue: number, adRevenue: number) {
  return [...day(date, { views, minutes: 0 }), revenue, adRevenue];
}

const MONEY_REPORT = {
  columnHeaders: MONEY_COLUMN_HEADERS,
  rows: [
    moneyDay("2026-10-01", 500, 1.111, 1.0),
    moneyDay("2026-10-02", 500, 2.222, 2.0),
    moneyDay("2026-10-03", 1000, 3.333, 3.0),
  ],
};

/** Routes the two reports apart by whether the request asked for money. */
function reports(options: { money?: unknown; plain?: unknown } = {}) {
  return {
    "/v2/reports": (url: URL) =>
      url.searchParams.get("metrics")?.includes("estimatedRevenue")
        ? (options.money ?? MONEY_REPORT)
        : (options.plain ?? REPORT),
  };
}

const FORBIDDEN = { __status: 403 };

describe("youtube", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("offers every owned channel, hinted by its handle", async () => {
    stubChannels([
      { id: "UC1", snippet: { title: "Main", customUrl: "@main" } },
      { id: "UC2", snippet: { title: "Clips" } },
    ]);
    const options = await youtube.oauth!.selection!.options(creds);
    expect(options).toEqual([
      { value: "UC1", label: "Main", hint: "@main" },
      { value: "UC2", label: "Clips", hint: undefined },
    ]);
  });

  it("says so when the Google account has no channel", async () => {
    stubChannels([]);
    await expect(youtube.oauth!.selection!.options(creds)).rejects.toMatchObject({
      code: "unsupported",
    });
  });

  it("names the connection after the channel and proves both APIs", async () => {
    const ctx = stubContext({ "/youtube/v3/channels": channelBody(), "/v2/reports": REPORT });
    const result = await youtube.verify(ctx, creds);
    expect(result.accountLabel).toBe("Notch Metrics");
    // The Data API alone would have verified a connection whose every metric
    // then failed on Analytics not being enabled.
    expect(ctx.calls.some((url) => url.includes("youtubeanalytics"))).toBe(true);
  });

  it("refuses a channel the account no longer has", async () => {
    const ctx = stubContext({ "/youtube/v3/channels": { items: [] } });
    await expect(youtube.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("sums views per day with gaps filled", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(1000);
    expect(series.points.map((p) => p.v)).toEqual([100, 300, 600, 0]);
    expect(series.note).toContain("behind");
  });

  it("reports watch time in seconds, not the minutes the API gives", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "watch_time" });
    expect(series.unit).toBe("duration");
    expect(series.value).toBe(450 * 60);
  });

  it("averages view duration over the window, not across the daily means", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, {
      ...request,
      metric: "average_view_duration",
    });
    // 27_000s / 1000 views, not the mean of 120, 30 and 10.
    expect(series.value).toBeCloseTo(27, 6);
    expect(series.unit).toBe("duration");
  });

  it("counts new subscribers gross, without deducting unsubscribes", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, {
      ...request,
      metric: "new_subscribers",
    });
    // 15 gained; the 10 lost are not netted off — that is `subscribers`.
    expect(series.value).toBe(15);
  });

  it("derives the previous subscriber total from the window's net change", async () => {
    const ctx = stubContext({ "/youtube/v3/channels": channelBody(), "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, {
      ...request,
      metric: "subscribers",
      comparePrevious: true,
    });
    expect(series.value).toBe(12_300);
    // Net +5 over the window, so the previous total was 12,295 — the delta is
    // exact even though the total YouTube reports is rounded.
    expect(series.previousValue).toBe(12_295);
    expect(series.points).toHaveLength(1);
  });

  it("refuses a channel that hides its subscriber count rather than reading zero", async () => {
    const ctx = stubContext({ "/youtube/v3/channels": channelBody(null) });
    await expect(
      youtube.fetchMetric(ctx, creds, { ...request, metric: "subscribers" }),
    ).rejects.toMatchObject({ code: "unsupported" });
  });

  it("asks for the previous window separately when comparing", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    const series = await youtube.fetchMetric(ctx, creds, { ...request, comparePrevious: true });
    const windows = ctx.calls.map((url) => {
      const params = new URL(url).searchParams;
      return [params.get("startDate"), params.get("endDate")];
    });
    expect(windows).toEqual([
      ["2026-10-01", "2026-10-04"],
      ["2026-09-28", "2026-09-30"],
    ]);
    expect(series.previousValue).toBe(1000);
  });

  it("pins the report to the chosen channel rather than YouTube's default", async () => {
    const ctx = stubContext({ "/v2/reports": REPORT });
    await youtube.fetchMetric(ctx, creds, request);
    expect(new URL(ctx.calls[0]!).searchParams.get("ids")).toBe(`channel==${creds.channel_id}`);
  });

  it("turns a 403 into advice about the APIs, not a rate limit", async () => {
    const ctx = stubContext({ "/v2/reports": { __status: 403 } });
    await expect(youtube.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "auth_failed",
    });
  });

  // The 10,000-unit daily budget, spent. YouTube answers 403 for this, not
  // 429, and it clears at midnight Pacific — so it is a wait, not a reason to
  // tell somebody their connection is broken and make them reconnect daily.
  it("reads a spent quota as a rate limit, not a dead connection", async () => {
    const ctx = stubContext({
      "/v2/reports": {
        __status: 403,
        __body: { error: { errors: [{ reason: "quotaExceeded" }], code: 403 } },
      },
    });
    await expect(youtube.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "rate_limited",
    });
  });

  it("rejects a report with no day column rather than charting zeroes", async () => {
    const ctx = stubContext({ "/v2/reports": { columnHeaders: [{ name: "views" }], rows: [[1]] } });
    await expect(youtube.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "bad_response",
    });
  });

  it("keeps revenue columns out of the report every channel can run", async () => {
    const ctx = stubContext(reports());
    await youtube.fetchMetric(ctx, creds, request);
    // A channel outside the Partner Program 403s the whole report if it
    // names a revenue column, taking the view count down with it.
    expect(scalar(ctx.calls[0])).not.toContain("estimatedRevenue");
    expect(new URL(scalar(ctx.calls[0])).searchParams.get("currency")).toBeNull();
  });

  it("rounds the window's revenue once, not every day of it", async () => {
    const ctx = stubContext(reports());
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "revenue" });
    expect(series.unit).toBe("currency");
    expect(series.currency).toBe("USD");
    // 6.666 summed then rounded. Rounding each day first would give 666.
    expect(series.value).toBe(667);
    // The chart still rounds per bucket, because a bucket is what it draws.
    expect(series.points.map((p) => p.v)).toEqual([111, 222, 333, 0]);
    expect(series.note).toContain("month-end");
  });

  it("separates ad revenue from total revenue", async () => {
    const ctx = stubContext(reports());
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "ad_revenue" });
    expect(series.value).toBe(600);
  });

  it("computes RPM per thousand views over the window, not per day", async () => {
    const ctx = stubContext(reports());
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "rpm" });
    // 6.666 over 2000 views × 1000 = 3.333. The mean of the daily RPMs would
    // be 3.333, 4.444 and 3.333 averaged — a different number.
    expect(series.value).toBe(333);
    expect(series.unit).toBe("currency");
  });

  it("asks YouTube to convert, rather than converting afterwards", async () => {
    const ctx = stubContext(reports(), { preferredCurrency: "GBP" });
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "revenue" });
    expect(new URL(scalar(ctx.calls[0])).searchParams.get("currency")).toBe("GBP");
    expect(series.currency).toBe("GBP");
  });

  it("falls back to USD for a currency YouTube cannot pay in, and says so", async () => {
    const ctx = stubContext(reports(), { preferredCurrency: "ISK" });
    const series = await youtube.fetchMetric(ctx, creds, { ...request, metric: "revenue" });
    expect(new URL(scalar(ctx.calls[0])).searchParams.get("currency")).toBe("USD");
    expect(series.currency).toBe("USD");
    expect(series.note).toContain("ISK");
  });

  it("reads a 403 on revenue as a channel without any, not a bad connection", async () => {
    const ctx = stubContext(reports({ money: FORBIDDEN }));
    await expect(
      youtube.fetchMetric(ctx, creds, { ...request, metric: "revenue" }),
    ).rejects.toMatchObject({ code: "unsupported" });
    // Not `auth_failed`: nothing here is fixed by reconnecting, and marking
    // the integration broken would stop the view counts working too.
  });

  it("offers revenue only to a channel that has it", async () => {
    const ctx = stubContext({ "/youtube/v3/channels": channelBody(), ...reports() });
    const result = await youtube.verify(ctx, creds);
    expect(result.availableMetrics).toContain("revenue");
    expect(result.currency).toBe("USD");
  });

  it("connects a channel outside the Partner Program, minus the revenue metrics", async () => {
    const ctx = stubContext({
      "/youtube/v3/channels": channelBody(),
      ...reports({ money: FORBIDDEN }),
    });
    const result = await youtube.verify(ctx, creds);
    // The connection is good. It just has a shorter menu.
    expect(result.availableMetrics).toContain("views");
    expect(result.availableMetrics).not.toContain("revenue");
    expect(result.availableMetrics).not.toContain("ad_revenue");
    expect(result.availableMetrics).not.toContain("rpm");
    expect(result.currency).toBeNull();
  });

  it("still fails verification when the whole Analytics API is refused", async () => {
    const ctx = stubContext({
      "/youtube/v3/channels": channelBody(),
      ...reports({ plain: FORBIDDEN, money: FORBIDDEN }),
    });
    await expect(youtube.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("requests the monetary scope, which covers the plain one", async () => {
    const scopes = youtube.oauth!.scopes;
    expect(scopes).toContain("https://www.googleapis.com/auth/yt-analytics-monetary.readonly");
    // Asking for both would be asking twice for the same thing.
    expect(scopes).not.toContain("https://www.googleapis.com/auth/yt-analytics.readonly");
  });

  it("does not claim a metric it cannot serve", async () => {
    const ctx = stubContext({});
    await expect(
      youtube.fetchMetric(ctx, creds, { ...request, metric: "mrr" }),
    ).rejects.toMatchObject({ code: "unsupported" });
  });
});
