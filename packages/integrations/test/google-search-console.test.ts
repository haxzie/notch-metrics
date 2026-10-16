import { afterEach, describe, expect, it, vi } from "vitest";
import { googleSearchConsole } from "../src/providers/google-search-console/index.ts";
import { stubContext } from "./helpers.ts";

const creds = { site: "sc-domain:example.com", access_token: "ya29.0123456789" };

const request = {
  metric: "clicks" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-04T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

function day(date: string, clicks: number, impressions: number, position: number) {
  return { keys: [date], clicks, impressions, ctr: clicks / impressions, position };
}

const rows = [
  day("2026-10-01", 10, 100, 5),
  day("2026-10-02", 30, 100, 15),
  // A day with ten times the impressions must weigh ten times as much.
  day("2026-10-03", 0, 1000, 50),
];

function stubSites(entries: { siteUrl: string; permissionLevel: string }[]) {
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ siteEntry: entries })));
}

describe("google search console", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("offers verified sites only, in the picker", async () => {
    stubSites([
      { siteUrl: "sc-domain:example.com", permissionLevel: "siteOwner" },
      { siteUrl: "https://old.example.com/", permissionLevel: "siteUnverifiedUser" },
    ]);
    const options = await googleSearchConsole.oauth!.selection!.options(creds);
    expect(options).toEqual([
      { value: "sc-domain:example.com", label: "sc-domain:example.com", hint: "Owner" },
    ]);
  });

  it("names the connection after the site, without Google's prefix", async () => {
    stubSites([{ siteUrl: "sc-domain:example.com", permissionLevel: "siteFullUser" }]);
    const result = await googleSearchConsole.verify(stubContext({}), creds);
    expect(result.accountLabel).toBe("example.com");
  });

  it("refuses a site the account no longer has", async () => {
    stubSites([]);
    await expect(googleSearchConsole.verify(stubContext({}), creds)).rejects.toMatchObject({
      code: "auth_failed",
    });
  });

  it("sums clicks per day with gaps filled", async () => {
    const ctx = stubContext({ "/searchAnalytics/query": { rows } });
    const series = await googleSearchConsole.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(40);
    expect(series.points.map((p) => p.v)).toEqual([10, 30, 0, 0]);
    expect(series.note).toContain("behind");
  });

  it("computes CTR from the sums, not the mean of daily rates", async () => {
    const ctx = stubContext({ "/searchAnalytics/query": { rows } });
    const series = await googleSearchConsole.fetchMetric(ctx, creds, { ...request, metric: "ctr" });
    // 40 / 1200, not (0.1 + 0.3 + 0) / 3.
    expect(series.value).toBeCloseTo(40 / 1200, 6);
    expect(series.unit).toBe("ratio");
  });

  it("weights average position by impressions, to one decimal", async () => {
    const ctx = stubContext({ "/searchAnalytics/query": { rows } });
    const series = await googleSearchConsole.fetchMetric(ctx, creds, {
      ...request,
      metric: "average_position",
    });
    // (5·100 + 15·100 + 50·1000) / 1200
    expect(series.value).toBeCloseTo(52000 / 1200, 6);
    expect(series.unit).toBe("count");
    expect(series.format).toEqual({ decimals: 1, compact: false });
  });

  it("asks for the previous window separately when comparing", async () => {
    const bodies: { startDate: string; endDate: string }[] = [];
    const ctx = stubContext({
      "/searchAnalytics/query": () => ({ rows: [day("2026-09-28", 5, 50, 3)] }),
    });
    const http = ctx.http;
    ctx.http = async (url, init) => {
      bodies.push(JSON.parse(String(init?.body)) as { startDate: string; endDate: string });
      return http(url, init);
    };
    const series = await googleSearchConsole.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: true,
    });
    expect(bodies.map((b) => [b.startDate, b.endDate])).toEqual([
      ["2026-10-01", "2026-10-04"],
      ["2026-09-28", "2026-09-30"],
    ]);
    expect(series.previousValue).toBe(5);
  });

  it("reads a quota 403 as a rate limit rather than a broken connection", async () => {
    const ctx = stubContext({
      "/searchAnalytics/query": {
        __status: 403,
        __body: { error: { errors: [{ reason: "userRateLimitExceeded" }], code: 403 } },
      },
    });
    await expect(googleSearchConsole.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "rate_limited",
    });
  });

  // The other half of the same status, preserved: a missing permission or a
  // disabled API really does need a human, and must keep saying so.
  it("still calls a permission 403 an auth failure", async () => {
    const ctx = stubContext({
      "/searchAnalytics/query": {
        __status: 403,
        __body: { error: { errors: [{ reason: "forbidden" }], code: 403 } },
      },
    });
    await expect(googleSearchConsole.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "auth_failed",
    });
  });
});
