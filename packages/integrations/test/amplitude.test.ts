import { describe, expect, it } from "vitest";
import { amplitude } from "../src/providers/amplitude/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = {
  api_key: "ampl1tudeapikey0123456789",
  secret_key: "ampl1tudesecret0123456789",
  region: "us" as const,
};

const request = {
  metric: "events" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
  params: {},
};

/** A Dashboard chart response: one unsegmented group, one value per day. */
function chart(days: Record<string, number>, collapsed?: number) {
  return {
    data: {
      xValues: Object.keys(days),
      series: [Object.values(days)],
      ...(collapsed === undefined ? {} : { seriesCollapsed: [[{ value: collapsed }]] }),
    },
  };
}

describe("amplitude verify", () => {
  it("proves the key pair with the smallest real query", async () => {
    const ctx = stubContext({ "/api/2/users": chart({ "2026-10-05": 7 }) });
    const result = await amplitude.verify(ctx, creds);

    expect(result.availableMetrics).toEqual(["events", "active_users", "new_users"]);
    // One day, today, because there is no identity endpoint to ask instead.
    const call = new URL(scalar(ctx.calls[0]));
    expect(call.searchParams.get("start")).toBe("20261005");
    expect(call.searchParams.get("end")).toBe("20261005");
  });

  it("signs with the pair as HTTP Basic", async () => {
    let sent: string | null = null;
    const ctx = stubContext({ "/api/2/users": chart({}) });
    const inner = ctx.http.bind(ctx);
    ctx.http = async (url: string, init?: RequestInit) => {
      sent = (init?.headers as Record<string, string> | undefined)?.authorization ?? null;
      return inner(url, init);
    };

    await amplitude.verify(ctx, creds);
    // The secret key is the password, not a bearer token.
    expect(sent).toBe(`Basic ${btoa(`${creds.api_key}:${creds.secret_key}`)}`);
  });

  it("names the region when the keys are rejected", async () => {
    const ctx = stubContext({ "/api/2/users": { __status: 401 } });
    // A US pair against the EU host answers 401 like a revoked key, and
    // somebody would otherwise spend the afternoon rolling a good secret.
    await expect(amplitude.verify(ctx, creds)).rejects.toMatchObject({
      code: "auth_failed",
      message: expect.stringContaining("US"),
    });
  });
});

describe("amplitude metrics", () => {
  it("sums the days for an additive metric and compares the window before", async () => {
    const ctx = stubContext({
      "/api/2/events/segmentation": (url: URL) =>
        url.searchParams.get("start") === "20261001"
          ? chart({ "2026-10-01": 40, "2026-10-03": 60 })
          : chart({ "2026-09-27": 70 }),
    });

    const series = await amplitude.fetchMetric(ctx, creds, request);

    expect(series.value).toBe(100);
    expect(series.previousValue).toBe(70);
    expect(series.unit).toBe("count");

    const call = new URL(scalar(ctx.calls[0]));
    expect(call.searchParams.get("e")).toBe(JSON.stringify({ event_type: "_all" }));
    expect(call.searchParams.get("m")).toBe("totals");
    // Daily always, then rolled up locally — Amplitude's own weeks start on
    // a Sunday and every other tile in the notch starts them on a Monday.
    expect(call.searchParams.get("i")).toBe("1");

    const compare = new URL(scalar(ctx.calls[1]));
    expect(compare.searchParams.get("start")).toBe("20260927");
    // The day before `from`, so the two windows do not share a day.
    expect(compare.searchParams.get("end")).toBe("20260930");
  });

  it("takes an active-user headline from Amplitude's own window figure", async () => {
    const ctx = stubContext({
      "/api/2/events/segmentation": chart({ "2026-10-01": 40, "2026-10-02": 45 }, 61),
    });

    const series = await amplitude.fetchMetric(ctx, creds, {
      ...request,
      metric: "active_users",
      comparePrevious: false,
    });

    // 61, not 85. Somebody active on both days is one active user.
    expect(series.value).toBe(61);
    expect(series.points.map((p) => p.v)).toEqual([40, 45, 0, 0, 0]);

    const call = new URL(scalar(ctx.calls[0]));
    expect(call.searchParams.get("e")).toBe(JSON.stringify({ event_type: "_active" }));
    expect(call.searchParams.get("m")).toBe("uniques");
  });

  it("falls back to the sum when no collapsed figure comes back", async () => {
    // An unexpectedly shaped response should under-report by de-duplication
    // it could not do, not report zero.
    const ctx = stubContext({
      "/api/2/events/segmentation": chart({ "2026-10-01": 40, "2026-10-02": 45 }),
    });
    const series = await amplitude.fetchMetric(ctx, creds, {
      ...request,
      metric: "active_users",
      comparePrevious: false,
    });
    expect(series.value).toBe(85);
  });

  it("asks the users endpoint for new users", async () => {
    const ctx = stubContext({ "/api/2/users": chart({ "2026-10-02": 9 }) });
    const series = await amplitude.fetchMetric(ctx, creds, {
      ...request,
      metric: "new_users",
      comparePrevious: false,
    });

    // A user is new on exactly one day, so the bars do add up.
    expect(series.value).toBe(9);
    expect(new URL(scalar(ctx.calls[0])).searchParams.get("m")).toBe("new");
  });

  it("rolls the days up into the bucket the widget asked for", async () => {
    const ctx = stubContext({
      "/api/2/events/segmentation": chart({ "2026-10-01": 10, "2026-10-02": 20 }),
    });
    const series = await amplitude.fetchMetric(ctx, creds, {
      ...request,
      granularity: "week",
      comparePrevious: false,
    });
    // Both days fall in the ISO week beginning Monday 28 September, so they
    // land in one bar. Oct 5 is itself a Monday, which opens the second,
    // still-empty week the window reaches into.
    expect(series.points.map((p) => p.v)).toEqual([30, 0]);
  });

  it("holds the series back when the widget only wants a number", async () => {
    const ctx = stubContext({ "/api/2/events/segmentation": chart({ "2026-10-01": 10 }) });
    const series = await amplitude.fetchMetric(ctx, creds, {
      ...request,
      wantSeries: false,
      comparePrevious: false,
    });
    expect(series.points).toEqual([]);
    expect(series.value).toBe(10);
  });

  it("uses the EU host for an EU project", async () => {
    const ctx = stubContext({ "/api/2/events/segmentation": chart({}) });
    await amplitude.fetchMetric(
      ctx,
      { ...creds, region: "eu" },
      { ...request, comparePrevious: false },
    );
    expect(scalar(ctx.calls[0])).toContain("analytics.eu.amplitude.com");
  });

  it("refuses a metric Amplitude has no answer for", async () => {
    const ctx = stubContext({ "/api/2/events/segmentation": chart({}) });
    await expect(
      amplitude.fetchMetric(ctx, creds, { ...request, metric: "mrr" }),
    ).rejects.toBeInstanceOf(ProviderError);
  });
});
