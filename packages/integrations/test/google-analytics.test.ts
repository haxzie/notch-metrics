import { describe, expect, it } from "vitest";
import { googleAnalytics } from "../src/providers/google-analytics/index.ts";
import { stubContext, expectMetrics } from "./helpers.ts";

const creds = { property_id: "123456", access_token: "ya29.0123456789" };

const request = {
  metric: "active_users" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

function row(date: string, value: number, range?: string) {
  return {
    dimensionValues: [{ value: date }, ...(range ? [{ value: range }] : [])],
    metricValues: [{ value: String(value) }],
  };
}

describe("google analytics", () => {
  it("names the connection after the property", async () => {
    const ctx = stubContext({
      "analyticsdata.googleapis.com": { rows: [] },
      "analyticsadmin.googleapis.com": { displayName: "Marketing site" },
    });
    const result = await googleAnalytics.verify(ctx, creds);
    expect(result.accountLabel).toBe("Marketing site");
    expectMetrics(result.availableMetrics, ["active_users", "new_users", "sessions", "pageviews"]);
  });

  it("still connects when the Admin API is not enabled, named by number", async () => {
    const ctx = stubContext({
      "analyticsdata.googleapis.com": { rows: [] },
      "analyticsadmin.googleapis.com": { __status: 403 },
    });
    expect((await googleAnalytics.verify(ctx, creds)).accountLabel).toBe("Property 123456");
  });

  it("takes the headline from GA's own total, not a sum of days", async () => {
    // Three users on three days may be one person. GA de-duplicates in the
    // totals row; the daily rows do not.
    const ctx = stubContext({
      "analyticsdata.googleapis.com": {
        rows: [row("20261001", 1), row("20261002", 1), row("20261003", 1)],
        totals: [
          { dimensionValues: [{ value: "RESERVED_TOTAL" }], metricValues: [{ value: "1" }] },
        ],
      },
    });
    const series = await googleAnalytics.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(1);
    expect(series.points.map((p) => p.v)).toEqual([1, 1, 1, 0, 0]);
  });

  it("splits the two windows GA returns in one response", async () => {
    const ctx = stubContext({
      "analyticsdata.googleapis.com": {
        rows: [row("20260928", 7, "date_range_1"), row("20261002", 3, "date_range_0")],
        totals: [
          {
            dimensionValues: [{ value: "RESERVED_TOTAL" }, { value: "date_range_0" }],
            metricValues: [{ value: "3" }],
          },
          {
            dimensionValues: [{ value: "RESERVED_TOTAL" }, { value: "date_range_1" }],
            metricValues: [{ value: "7" }],
          },
        ],
      },
    });
    const series = await googleAnalytics.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: true,
    });
    expect(series.value).toBe(3);
    expect(series.previousValue).toBe(7);
    expect(series.points.reduce((s, p) => s + p.v, 0)).toBe(3);
  });

  it("reads an empty comparison window as zero, not as a broken provider", async () => {
    // Google sends `{}` for a date range it found no data at all in, with no
    // dimension values to match the range name against. A property younger
    // than the window behind the one being asked for — any 90d or 12m tile on
    // a site set up three months ago — hits this every time, and reading
    // `.dimensionValues` off it failed the tile with "could not be reached".
    const ctx = stubContext({
      "analyticsdata.googleapis.com": {
        rows: [row("20261002", 3, "date_range_0")],
        totals: [
          {
            dimensionValues: [{ value: "RESERVED_TOTAL" }, { value: "date_range_0" }],
            metricValues: [{ value: "3" }],
          },
          {},
        ],
      },
    });
    const series = await googleAnalytics.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: true,
    });
    expect(series.value).toBe(3);
    expect(series.previousValue).toBe(0);
  });

  it("still reads the headline when it is the current window Google emptied", async () => {
    const ctx = stubContext({
      "analyticsdata.googleapis.com": {
        rows: [],
        totals: [
          {},
          {
            dimensionValues: [{ value: "RESERVED_TOTAL" }, { value: "date_range_1" }],
            metricValues: [{ value: "7" }],
          },
        ],
      },
    });
    const series = await googleAnalytics.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: true,
    });
    expect(series.value).toBe(0);
    expect(series.previousValue).toBe(7);
  });

  it("asks for the right GA4 metric name", async () => {
    const seen: string[] = [];
    const ctx = stubContext({
      "analyticsdata.googleapis.com": (url: URL) => {
        seen.push(url.pathname);
        return { rows: [] };
      },
    });
    await googleAnalytics.fetchMetric(ctx, creds, { ...request, metric: "pageviews" });
    expect(seen[0]).toContain("/properties/123456:runReport");
  });

  it("reads a quota 403 as a rate limit rather than a broken connection", async () => {
    const ctx = stubContext({
      "analyticsdata.googleapis.com": {
        __status: 403,
        __body: { error: { errors: [{ reason: "rateLimitExceeded" }], code: 403 } },
      },
    });
    await expect(googleAnalytics.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "rate_limited",
    });
  });

  it("explains a 403 rather than calling the token bad", async () => {
    const ctx = stubContext({ "analyticsdata.googleapis.com": { __status: 403 } });
    await expect(googleAnalytics.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "auth_failed",
      message: expect.stringContaining("Data API"),
    });
  });
});
