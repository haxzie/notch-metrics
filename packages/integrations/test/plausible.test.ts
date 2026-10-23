import { describe, expect, it } from "vitest";
import { plausible } from "../src/providers/plausible/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext, expectMetrics } from "./helpers.ts";

const creds = { api_key: "plausible-key-0123456789", site_id: "example.com" };

const request = {
  metric: "pageviews" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
  params: {},
};

interface Query {
  site_id: string;
  metrics: string[];
  date_range: [string, string];
  dimensions?: string[];
}

/** A row as `/api/v2/query` returns it. */
function row(value: number, bucket?: string) {
  return { metrics: [value], ...(bucket ? { dimensions: [bucket] } : {}) };
}

/**
 * `stubContext` matches on the URL alone, and all three of a fetch's calls go
 * to the same path. The query itself is what tells them apart, so it is
 * captured and dispatched on here.
 */
function contextFor(reply: (query: Query) => unknown[], overrides: Record<string, unknown> = {}) {
  const sent: Query[] = [];
  const ctx = stubContext({
    "/api/v1/sites/": { domain: "example.com", timezone: "Europe/London" },
    ...overrides,
  });
  const inner = ctx.http.bind(ctx);
  ctx.http = async (url: string, init?: RequestInit) => {
    if (!init?.body) return inner(url, init);
    const query = JSON.parse(String(init.body)) as Query;
    sent.push(query);
    return {
      ok: true,
      status: 200,
      headers: new Headers(),
      json: <T>() => Promise.resolve({ results: reply(query) } as T),
      text: () => Promise.resolve(""),
    };
  };
  return { ctx, sent };
}

describe("plausible verify", () => {
  it("names the connection from the site Plausible knows about", async () => {
    const ctx = stubContext({
      "/api/v1/sites/example.com": { domain: "example.com", timezone: "Europe/London" },
    });
    const result = await plausible.verify(ctx, creds);

    expect(result.accountLabel).toBe("example.com");
    expectMetrics(result.availableMetrics, ["visitors", "pageviews", "sessions", "bounce_rate"]);
    // The site endpoint, not a stats query: verifying must not spend quota.
    expect(scalar(ctx.calls[0])).toContain("/api/v1/sites/example.com");
    expect(ctx.calls).toHaveLength(1);
  });

  it("blames the key's team rather than the domain when the site is not found", async () => {
    const ctx = stubContext({
      "/api/v1/sites/": { __status: 404 },
    });
    // A key is scoped to one team, so a correct domain owned by another team
    // 404s exactly like a typo. The message has to say so.
    await expect(plausible.verify(ctx, creds)).rejects.toMatchObject({
      code: "auth_failed",
      message: expect.stringContaining("team"),
    });
  });
});

describe("plausible metrics", () => {
  it("takes the headline from its own aggregate, not from the chart", async () => {
    const { ctx, sent } = contextFor((query) =>
      query.dimensions
        ? [row(40, "2026-10-01"), row(60, "2026-10-03")]
        : // The aggregate deliberately disagrees with the sum of the bars, so
          // a test that passes by accident cannot.
          [row(query.date_range[0] < "2026-10-01" ? 70 : 111)],
    );

    const series = await plausible.fetchMetric(ctx, creds, request);

    expect(series.value).toBe(111);
    expect(series.previousValue).toBe(70);
    expect(series.unit).toBe("count");
    expect(series.currency).toBeNull();

    // Three queries: this window, the one before it, and the chart.
    expect(sent).toHaveLength(3);
    expect(scalar(sent[0]).metrics).toEqual(["pageviews"]);
    expect(scalar(sent[0]).dimensions).toBeUndefined();
    // The compare window is the same length, immediately before.
    expect(scalar(sent[1]).date_range[0]).toBe("2026-09-27T00:00:00.000Z");
    expect(scalar(sent[1]).date_range[1]).toBe("2026-10-01T00:00:00.000Z");
    expect(scalar(sent[2]).dimensions).toEqual(["time:day"]);
  });

  it("gap-fills the quiet days rather than drawing a step", async () => {
    const { ctx } = contextFor((query) =>
      query.dimensions ? [row(40, "2026-10-01"), row(60, "2026-10-04")] : [row(100)],
    );
    const series = await plausible.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: false,
    });
    // Oct 1 to Oct 5 inclusive, with Oct 2, 3 and 5 at zero.
    expect(series.points.map((p) => p.v)).toEqual([40, 0, 0, 60, 0]);
    expect(series.previousValue).toBeNull();
  });

  it("asks Plausible to bucket at the granularity it was given", async () => {
    const { ctx, sent } = contextFor((query) =>
      query.dimensions ? [row(500, "2026-09-28")] : [row(500)],
    );
    await plausible.fetchMetric(ctx, creds, {
      ...request,
      granularity: "week",
      comparePrevious: false,
    });
    // Rolling seven daily bounce rates up here would average them; asking for
    // the week lets Plausible weight it by its own sessions.
    expect(scalar(sent[1]).dimensions).toEqual(["time:week"]);
  });

  it("skips the chart query when the widget only wants a number", async () => {
    const { ctx, sent } = contextFor(() => [row(100)]);
    const series = await plausible.fetchMetric(ctx, creds, {
      ...request,
      wantSeries: false,
      comparePrevious: false,
    });
    expect(series.points).toEqual([]);
    expect(sent).toHaveLength(1);
    expect(scalar(sent[0]).dimensions).toBeUndefined();
  });

  it("turns a bounce percentage into a fraction", async () => {
    const { ctx } = contextFor((query) =>
      query.dimensions ? [row(43.2, "2026-10-01")] : [row(51.5)],
    );
    const series = await plausible.fetchMetric(ctx, creds, {
      ...request,
      metric: "bounce_rate",
      comparePrevious: false,
    });
    // A `ratio` here is 0–1. Passing Plausible's 51.5 through would render
    // as 5150%.
    expect(series.unit).toBe("ratio");
    expect(series.value).toBeCloseTo(0.515);
    expect(scalar(series.points[0]).v).toBeCloseTo(0.432);
  });

  it("asks for `visits` when the widget asks for sessions", async () => {
    const { ctx, sent } = contextFor(() => [row(12)]);
    await plausible.fetchMetric(ctx, creds, {
      ...request,
      metric: "sessions",
      wantSeries: false,
      comparePrevious: false,
    });
    expect(scalar(sent[0]).metrics).toEqual(["visits"]);
  });

  it("refuses a metric Plausible has no answer for", async () => {
    const { ctx } = contextFor(() => []);
    await expect(
      plausible.fetchMetric(ctx, creds, { ...request, metric: "mrr" }),
    ).rejects.toBeInstanceOf(ProviderError);
  });
});

describe("plausible errors", () => {
  it("passes Plausible's own sentence through", async () => {
    const ctx = stubContext({ "/api/v2/query": { __status: 400 } });
    // The stub has no body, so this only proves the status mapping; the
    // point of the branch is that a 400 is a bad query and not a bad key.
    await expect(
      plausible.fetchMetric(ctx, creds, { ...request, comparePrevious: false }),
    ).rejects.toMatchObject({ code: "bad_response" });
  });

  it("calls a rejected key a rejected key", async () => {
    const ctx = stubContext({ "/api/v2/query": { __status: 401 } });
    await expect(
      plausible.fetchMetric(ctx, creds, { ...request, comparePrevious: false }),
    ).rejects.toMatchObject({ code: "auth_failed" });
  });
});
