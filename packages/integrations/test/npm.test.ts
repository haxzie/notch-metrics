import { describe, expect, it } from "vitest";
import { npm } from "../src/providers/npm/index.ts";
import { ProviderError } from "../src/types.ts";
import { expectMetrics, refusedOfferedRanges, scalar, stubContext } from "./helpers.ts";

// Empty: npm's download counts are public, so there is no credential.
const creds = {};

const request = {
  metric: "downloads" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: { package: "react" },
};

/** A day as `/downloads/range` returns it. */
function day(date: string, downloads: number) {
  return { day: date, downloads };
}

const RANGE = {
  start: "2026-10-01",
  end: "2026-10-05",
  package: "react",
  downloads: [
    day("2026-10-01", 100),
    day("2026-10-02", 200),
    day("2026-10-03", 300),
    day("2026-10-04", 400),
    day("2026-10-05", 500),
  ],
};

const routes = {
  "/downloads/range/": RANGE,
  "/downloads/point/last-week/": {
    downloads: 2500,
    start: "2026-09-28",
    end: "2026-10-04",
    package: "react",
  },
  "/-/whoami": { username: "haxzie" },
};

describe("npm", () => {
  /// Connecting reaches nothing. A token would only have named the
  /// connection, and npm charges a trip through 2FA for one.
  it("connects without a credential and without a request", async () => {
    const ctx = stubContext(routes);
    const result = await npm.verify(ctx, creds);
    expect(result.accountLabel).toBe("npm");
    expect(ctx.calls).toEqual([]);
  });

  it("declares itself as needing no credentials", () => {
    expect(npm.manifest.authMode).toBe("none");
    expect(npm.manifest.fields).toEqual([]);
  });

  it("offers both metrics", async () => {
    const ctx = stubContext(routes);
    const result = await npm.verify(ctx, creds);
    expect(result.availableMetrics).toEqual(["downloads", "weekly_downloads"]);
  });

  it("sums the window from the days, not from the buckets", async () => {
    const ctx = stubContext(routes);
    const series = await npm.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(1500);
    expect(series.points).toHaveLength(5);
  });

  /**
   * npm publishes days and only days, so a weekly chart is rolled up here.
   * Getting this wrong by asking npm for a week would start weeks on npm's
   * boundary rather than the reader's.
   */
  it("rolls daily counts up into the bucket the chart asked for", async () => {
    const ctx = stubContext(routes);
    const series = await npm.fetchMetric(ctx, creds, {
      ...request,
      granularity: "week",
    });
    expect(series.value).toBe(1500);
    expect(series.points.reduce((sum, point) => sum + point.v, 0)).toBe(1500);
    expect(series.points.length).toBeLessThan(5);
  });

  /**
   * A UTC day read at midnight into a zone behind UTC lands on the day
   * before, which shifts every bar by one and is invisible unless somebody
   * counts. Midday is what keeps the bar where npm put it.
   */
  it("keeps a day on its own day in a zone behind UTC", async () => {
    const ctx = stubContext(routes, { timeZone: "America/Los_Angeles" });
    const series = await npm.fetchMetric(ctx, creds, request);

    // npm's 1 October lands in the bucket Los Angeles calls 1 October.
    // Parsed at midnight instead of midday, that day's 100 downloads would
    // fall in the 30 September bucket and every bar in the chart would sit
    // one day to the left of where npm put it.
    //
    // The date part only: `bucketStart` labels a bucket with the UTC
    // midnight of the local day, so the instant is not the local day's start
    // and asserting on it would be pinning a representation rather than the
    // behaviour.
    const landed = series.points.find((point) => point.v === 100);
    expect(landed?.t.toISOString().slice(0, 10)).toBe("2026-10-01");
  });

  it("asks npm for the window's own UTC days", async () => {
    const ctx = stubContext(routes);
    await npm.fetchMetric(ctx, creds, request);
    expect(ctx.calls.some((url) => url.includes("/downloads/range/2026-10-01:2026-10-05/"))).toBe(
      true,
    );
  });

  /**
   * npm backfills late and scattered, not just at the end: September 2026 had
   * gaps on the 7th, 8th and 15th. A note that said "today is not counted
   * yet" would be wrong about where the zeros are and why.
   */
  it("counts every unaggregated day, not only a trailing one", async () => {
    const ctx = stubContext({
      ...routes,
      "/downloads/range/": {
        ...RANGE,
        downloads: [
          day("2026-10-01", 100),
          day("2026-10-02", 0),
          day("2026-10-03", 300),
          day("2026-10-04", 0),
          day("2026-10-05", 500),
        ],
      },
    });
    const series = await npm.fetchMetric(ctx, creds, request);
    expect(series.note).toMatch(/2 of 5 days/);
  });

  /**
   * Comparing a window npm has three gaps in against one it has none in
   * reports npm's own backlog as a fall in downloads. Better to withhold the
   * delta and say why.
   */
  it("withholds the comparison when the two windows are aggregated differently", async () => {
    let call = 0;
    const ctx = stubContext({
      ...routes,
      "/downloads/range/": () => {
        call += 1;
        // The window asked for first has two gaps; the one before has none.
        return call === 1
          ? {
              ...RANGE,
              downloads: [day("2026-10-01", 0), day("2026-10-02", 0), day("2026-10-03", 300)],
            }
          : {
              ...RANGE,
              downloads: [day("2026-09-28", 10), day("2026-09-29", 20), day("2026-09-30", 30)],
            };
      },
    });

    const series = await npm.fetchMetric(ctx, creds, { ...request, comparePrevious: true });
    // Null rather than undefined: `toRawSeries` normalises an absent
    // comparison on the way out.
    expect(series.previousValue).toBeNull();
    expect(series.note).toMatch(/no comparison/i);
  });

  it("compares when both windows are aggregated to the same depth", async () => {
    const ctx = stubContext({
      ...routes,
      "/downloads/range/": {
        ...RANGE,
        downloads: [day("2026-10-01", 100), day("2026-10-02", 200)],
      },
    });
    const series = await npm.fetchMetric(ctx, creds, { ...request, comparePrevious: true });
    expect(series.previousValue).toBe(300);
  });

  /**
   * npm's "Weekly Downloads" is a trailing seven-day sum, not a calendar
   * week: react's 248,185,175 on 4 November is exactly the seven days ending
   * that day. Calendar weeks gave 116M and 243M on consecutive weeks,
   * because npm's counts service had no data at all for 13–15 and 19–21
   * October and a week holding three of those came out half empty.
   */
  it("reports a trailing seven-day sum, not a calendar week", async () => {
    // Ten days of 100, so every full week is exactly 700.
    const ten = Array.from({ length: 10 }, (_, i) =>
      day(`2026-10-${String(i + 1).padStart(2, "0")}`, 100),
    );
    const ctx = stubContext({ ...routes, "/downloads/range/": { ...RANGE, downloads: ten } });

    const result = await npm.fetchMetric(ctx, creds, {
      ...request,
      metric: "weekly_downloads",
      from: new Date("2026-10-07T00:00:00Z"),
      to: new Date("2026-10-10T00:00:00Z"),
    });
    expect(result.value).toBe(700);
    // One point per day, each its own trailing week — never a weekly bar.
    expect(result.points.every((point) => point.v === 700)).toBe(true);
  });

  /**
   * Trailing uncounted days drag the rolling total down: react fell from
   * 248M to 171M across two of them. npm's own page ends at the last
   * complete day instead, and so does this.
   */
  it("ends at the last day npm has counted, not at an uncounted zero", async () => {
    const days = [
      ...Array.from({ length: 8 }, (_, i) => day(`2026-10-${String(i + 1).padStart(2, "0")}`, 100)),
      day("2026-10-09", 0),
      day("2026-10-10", 0),
    ];
    const ctx = stubContext({ ...routes, "/downloads/range/": { ...RANGE, downloads: days } });

    const result = await npm.fetchMetric(ctx, creds, {
      ...request,
      metric: "weekly_downloads",
      from: new Date("2026-10-07T00:00:00Z"),
      to: new Date("2026-10-10T00:00:00Z"),
    });
    // 700, not the 500 the two trailing zeros would have produced.
    expect(result.value).toBe(700);
  });

  /** A scoped name carries a slash, which is the one character that would
   *  otherwise address a different endpoint on an allowed host. */
  it("encodes a scope without turning its slash into a path", async () => {
    const ctx = stubContext(routes);
    await npm.fetchMetric(ctx, creds, {
      ...request,
      params: { package: "@scope/name" },
    });
    expect(ctx.calls.some((url) => url.includes("%40scope/name"))).toBe(true);
  });

  it("refuses a package name that is not one, rather than building a URL from it", async () => {
    const ctx = stubContext(routes);
    const error = await npm
      .fetchMetric(ctx, creds, { ...request, params: { package: "../../etc" } })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
  });

  it("says which widget needs attention when no package is set", async () => {
    const ctx = stubContext(routes);
    const error = await npm
      .fetchMetric(ctx, creds, { ...request, params: {} })
      .catch((e: unknown) => e);
    expect((error as ProviderError).message).toMatch(/pick a package/i);
  });

  /**
   * Blames the package, not the connection. The same token answers every
   * other tile, so marking the integration broken would ask the user to
   * replace a credential that works.
   */
  it("blames the package for a 404", async () => {
    const ctx = stubContext({ ...routes, "/downloads/range/": { __status: 404 } });
    const error = await npm.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
    expect((error as ProviderError).message).toMatch(/could not be read/i);
  });

  /** There is no credential to send, and no authorization header either. */
  it("sends no authorization header at all", async () => {
    const sent: (RequestInit | undefined)[] = [];
    const ctx = stubContext({
      "/downloads/range/": (_url: URL, init?: RequestInit) => {
        sent.push(init);
        return RANGE;
      },
    });
    await npm.fetchMetric(ctx, creds, request);
    expect(sent.length).toBeGreaterThan(0);
    for (const init of sent) {
      expect(JSON.stringify(init?.headers ?? {}).toLowerCase()).not.toContain("authorization");
    }
  });

  it("declares the package on both metrics", () => {
    for (const metric of npm.manifest.metrics) {
      expect(metric.params?.map((param) => param.key)).toContain("package");
    }
  });

  it("refuses a metric it does not provide", async () => {
    const ctx = stubContext(routes);
    const error = await npm
      .fetchMetric(ctx, creds, { ...request, metric: "mrr" })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
  });

  /**
   * The combination nobody writes a case for is the one that reaches a tile.
   * Asserts the adapter answers every range its own `granularities` promise.
   */
  it("serves every range its manifest offers", async () => {
    expect(
      await refusedOfferedRanges(npm, creds, routes, {
        params: {
          downloads: { package: "react" },
          weekly_downloads: { package: "react" },
        },
      }),
    ).toEqual([]);
  });
});
