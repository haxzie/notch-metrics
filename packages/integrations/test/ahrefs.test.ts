import { describe, expect, it } from "vitest";
import { ahrefs } from "../src/providers/ahrefs/index.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { api_key: "ahrefs-0123456789", target: "example.com" };

const request = {
  metric: "domain_rating" as const,
  granularity: "day" as const,
  from: new Date("2026-10-03T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
};

const LIMITS = {
  "/subscription-info/limits-and-usage": {
    limits_and_usage: { subscription: "advanced", units_limit_api_key: 1_000_000 },
  },
};

/** Five days of DR, so a two-day window has two days of history behind it. */
const domainRatings = [
  { date: "2026-10-01", domain_rating: 60 },
  { date: "2026-10-02", domain_rating: 62 },
  { date: "2026-10-03", domain_rating: 70 },
  { date: "2026-10-04", domain_rating: 71 },
  { date: "2026-10-05", domain_rating: 73 },
];

describe("ahrefs", () => {
  it("verifies against the free endpoint, so connecting costs no units", async () => {
    const ctx = stubContext(LIMITS);
    const result = await ahrefs.verify(ctx, creds);
    expect(result.accountLabel).toBe("example.com");
    expect(result.availableMetrics).toContain("domain_rating");
    expect(ctx.calls).toHaveLength(1);
    expect(scalar(ctx.calls[0])).toContain("/subscription-info/limits-and-usage");
  });

  it("reduces a pasted URL to the domain, which is what Site Explorer scopes to", async () => {
    const result = await ahrefs.verify(stubContext(LIMITS), {
      ...creds,
      target: "  HTTPS://Example.com/blog/post  ",
    });
    expect(result.accountLabel).toBe("example.com");
  });

  it("explains a 403 as a plan problem rather than a bad key", async () => {
    const ctx = stubContext({ "/subscription-info/limits-and-usage": { __status: 403 } });
    await expect(ahrefs.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
    await expect(ahrefs.verify(ctx, creds)).rejects.toThrow(/eligible paid plan/);
  });

  it("surfaces a rate limit as rate_limited, not as a bad response", async () => {
    const ctx = stubContext({
      "/subscription-info/limits-and-usage": { __status: 429, __headers: { "retry-after": "30" } },
    });
    await expect(ahrefs.verify(ctx, creds)).rejects.toMatchObject({
      code: "rate_limited",
      retryAfterSeconds: 30,
    });
  });

  it("reports domain rating as the latest reading, never the sum", async () => {
    const ctx = stubContext({
      "/site-explorer/domain-rating-history": { domain_ratings: domainRatings },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, request);
    // 73 at the end of the window, not 70 + 71 + 73.
    expect(series.value).toBe(73);
    expect(series.points.map((p) => p.v)).toEqual([70, 71, 73]);
    expect(series.unit).toBe("count");
  });

  it("renders DR as a whole number rather than a percentage", async () => {
    const ctx = stubContext({
      "/site-explorer/domain-rating-history": { domain_ratings: domainRatings },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, request);
    // A `ratio` unit would render 73 as "7300%", and compacting would make
    // a three-digit score read "0.1k".
    expect(series.format).toEqual({ decimals: 0, compact: false });
  });

  it("compares against the previous window within one billed call", async () => {
    const ctx = stubContext({
      "/site-explorer/domain-rating-history": { domain_ratings: domainRatings },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, { ...request, comparePrevious: true });
    expect(series.value).toBe(73);
    // The last reading before the window opened, not the first of the window.
    expect(series.previousValue).toBe(62);
    expect(ctx.calls).toHaveLength(1);
    expect(scalar(ctx.calls[0])).toContain("date_from=2026-10-01");
  });

  it("asks only for the window when no comparison was requested", async () => {
    const ctx = stubContext({
      "/site-explorer/domain-rating-history": { domain_ratings: domainRatings },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, request);
    expect(series.previousValue).toBeNull();
    expect(scalar(ctx.calls[0])).toContain("date_from=2026-10-03");
  });

  it("totals organic keywords across the position buckets that partition the top 100", async () => {
    const ctx = stubContext({
      "/site-explorer/keywords-history": {
        keywords: [
          // top11_plus already contains top21_50 and top51_plus; adding those
          // would count the same keywords twice.
          { date: "2026-10-03", top3: 5, top4_10: 10, top11_plus: 85, top21_50: 60 },
          { date: "2026-10-05", top3: 6, top4_10: 12, top11_plus: 90, top51_plus: 40 },
        ],
      },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, { ...request, metric: "organic_keywords" });
    expect(series.points.map((p) => p.v)).toEqual([100, 108]);
    expect(series.value).toBe(108);
  });

  it("maps our granularity onto Ahrefs' own grouping", async () => {
    const ctx = stubContext({
      "/site-explorer/domain-rating-history": { domain_ratings: domainRatings },
    });
    await ahrefs.fetchMetric(ctx, creds, { ...request, granularity: "week" });
    expect(scalar(ctx.calls[0])).toContain("history_grouping=weekly");
  });

  it("counts live backlinks, not all-time", async () => {
    const ctx = stubContext({
      "/site-explorer/backlinks-stats": { metrics: { live: 1_200, all_time: 9_999 } },
    });
    const series = await ahrefs.fetchMetric(ctx, creds, { ...request, metric: "backlinks" });
    expect(series.value).toBe(1_200);
    // No history endpoint exists, so one reading — not a line invented from it.
    expect(series.points).toHaveLength(1);
    expect(ctx.calls).toHaveLength(1);
  });

  it("takes a second backlinks reading only when a delta was asked for", async () => {
    const ctx = stubContext({
      "/site-explorer/backlinks-stats": (url: URL) => ({
        metrics: { live: url.searchParams.get("date") === "2026-10-05" ? 1_200 : 1_000 },
      }),
    });
    const series = await ahrefs.fetchMetric(ctx, creds, {
      ...request,
      metric: "backlinks",
      comparePrevious: true,
    });
    expect(series.value).toBe(1_200);
    expect(series.previousValue).toBe(1_000);
    expect(ctx.calls).toHaveLength(2);
  });

  it("refuses a metric it does not provide", async () => {
    const ctx = stubContext({});
    await expect(
      ahrefs.fetchMetric(ctx, creds, { ...request, metric: "mrr" }),
    ).rejects.toMatchObject({ code: "unsupported" });
  });
});
