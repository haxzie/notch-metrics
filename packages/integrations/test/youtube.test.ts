import { afterEach, describe, expect, it, vi } from "vitest";
import { youtube } from "../src/providers/youtube/index.ts";
import { stubContext } from "./helpers.ts";

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

  it("rejects a report with no day column rather than charting zeroes", async () => {
    const ctx = stubContext({ "/v2/reports": { columnHeaders: [{ name: "views" }], rows: [[1]] } });
    await expect(youtube.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "bad_response",
    });
  });

  it("does not claim a metric it cannot serve", async () => {
    const ctx = stubContext({});
    await expect(
      youtube.fetchMetric(ctx, creds, { ...request, metric: "mrr" }),
    ).rejects.toMatchObject({ code: "unsupported" });
  });
});
