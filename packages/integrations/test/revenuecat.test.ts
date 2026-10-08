import { describe, expect, it } from "vitest";
import { revenuecat, toMinorUnits } from "../src/providers/revenuecat/index.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { secret_key: "sk_abcdefghijklmnopqrstuvwxyz", project_id: "proj1" };

const projects = {
  object: "list",
  items: [{ object: "project", id: "proj1", name: "MagicWeather", created_at: 1 }],
  next_page: null,
  url: "/v2/projects",
};

function card(id: string, value: number, period = "P0D") {
  return {
    object: "overview_metric",
    id,
    name: id,
    description: "",
    unit: id === "mrr" ? "$" : "#",
    period,
    value,
    last_updated_at: 1_759_600_000_000,
    last_updated_at_iso8601: "2026-10-04T18:40:00+00:00",
  };
}

const overview = (currency = "USD") => ({
  object: "overview_metrics",
  currency,
  metrics: [
    card("active_trials", 42),
    card("active_subscriptions", 1_234),
    card("mrr", 12_345.67),
    card("revenue", 50_000.12, "P28D"),
    card("new_customers", 900, "P28D"),
    card("active_users", 7_500, "P28D"),
  ],
});

const snapshot = {
  metric: "mrr" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: false,
};

describe("revenuecat money", () => {
  it("turns RevenueCat's decimal major units into integer minor units", () => {
    expect(toMinorUnits(12_345.67, "USD")).toBe(1_234_567);
    // Floating point: 0.1 + 0.2 territory must not leak into a cent count.
    expect(toMinorUnits(19.99, "EUR")).toBe(1_999);
  });

  it("does not multiply a zero-decimal currency", () => {
    expect(toMinorUnits(1_234, "JPY")).toBe(1_234);
    expect(toMinorUnits(1_234, "KRW")).toBe(1_234);
  });
});

describe("revenuecat overview metrics", () => {
  it("reads MRR off the overview as a snapshot in minor units", async () => {
    const ctx = stubContext({ "/metrics/overview": overview() });
    const series = await revenuecat.fetchMetric(ctx, creds, snapshot);
    expect(series.value).toBe(1_234_567);
    expect(series.currency).toBe("USD");
    expect(series.unit).toBe("currency");
    expect(series.points).toHaveLength(1);
    expect(scalar(series.points[0]).t).toEqual(ctx.now());
    expect(series.previousValue).toBeNull();
    expect(series.asOf).toEqual(new Date(1_759_600_000_000));
  });

  it("asks for the user's currency and reports what came back", async () => {
    const ctx = stubContext({ "/metrics/overview": overview("EUR") }, { preferredCurrency: "EUR" });
    const series = await revenuecat.fetchMetric(ctx, creds, snapshot);
    expect(scalar(ctx.calls[0])).toContain("currency=EUR");
    expect(series.currency).toBe("EUR");
    expect(series.note).toBeUndefined();
  });

  it("falls back to RevenueCat's default for a currency it cannot report in, and says so", async () => {
    const ctx = stubContext({ "/metrics/overview": overview("USD") }, { preferredCurrency: "INR" });
    const series = await revenuecat.fetchMetric(ctx, creds, snapshot);
    expect(scalar(ctx.calls[0])).not.toContain("currency=");
    expect(series.currency).toBe("USD");
    expect(series.note).toContain("INR");
  });

  it("maps each count card to its metric", async () => {
    const ctx = stubContext({ "/metrics/overview": overview() });
    const expectations = {
      active_subscribers: 1_234,
      trials: 42,
      new_users: 900,
      active_users: 7_500,
    } as const;
    for (const [metric, expected] of Object.entries(expectations)) {
      const series = await revenuecat.fetchMetric(ctx, creds, {
        ...snapshot,
        metric: metric as keyof typeof expectations,
      });
      expect(series.value, metric).toBe(expected);
      expect(series.unit, metric).toBe("count");
      expect(series.currency, metric).toBeNull();
    }
  });

  it("fails loudly when a card is missing rather than showing zero", async () => {
    const ctx = stubContext({
      "/metrics/overview": { object: "overview_metrics", currency: "USD", metrics: [] },
    });
    await expect(revenuecat.fetchMetric(ctx, creds, snapshot)).rejects.toMatchObject({
      code: "bad_response",
    });
  });

  it("does not list projects when the project id is given", async () => {
    const ctx = stubContext({ "/metrics/overview": overview() });
    await revenuecat.fetchMetric(ctx, creds, snapshot);
    expect(ctx.calls.some((url) => url.endsWith("/v2/projects?limit=100"))).toBe(false);
    expect(scalar(ctx.calls[0])).toContain("/v2/projects/proj1/metrics/overview");
  });
});

describe("revenuecat revenue", () => {
  const request = { ...snapshot, metric: "revenue" as const, comparePrevious: true };

  it("totals the window and the one before it with inclusive calendar days", async () => {
    const ctx = stubContext({
      "/metrics/revenue": (url: URL) => ({
        object: "revenue_metric",
        start_date: url.searchParams.get("start_date"),
        end_date: url.searchParams.get("end_date"),
        currency: "USD",
        value: url.searchParams.get("end_date") === "2026-10-05" ? 1_000.5 : 800.25,
        revenue_type: "revenue",
      }),
    });
    const series = await revenuecat.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(100_050);
    expect(series.previousValue).toBe(80_025);

    const [current, previous] = ctx.calls.map((url) => new URL(url).searchParams);
    expect(scalar(current).get("start_date")).toBe("2026-09-05");
    expect(scalar(current).get("end_date")).toBe("2026-10-05");
    // The previous window ends the day before the current one starts, or
    // 5 September is counted in both.
    expect(scalar(previous).get("end_date")).toBe("2026-09-04");
    expect(scalar(previous).get("start_date")).toBe("2026-08-05");
    expect(scalar(current).get("revenue_type")).toBe("revenue");
  });

  it("skips the second call when no comparison is wanted", async () => {
    const ctx = stubContext({
      "/metrics/revenue": {
        object: "revenue_metric",
        start_date: "2026-09-05",
        end_date: "2026-10-05",
        currency: "USD",
        value: 10,
        revenue_type: "revenue",
      },
    });
    const series = await revenuecat.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: false,
    });
    expect(series.value).toBe(1_000);
    expect(series.previousValue).toBeNull();
    expect(ctx.calls).toHaveLength(1);
  });

  it("uses the user's calendar, not UTC's, for the day boundaries", async () => {
    const ctx = stubContext(
      {
        "/metrics/revenue": {
          object: "revenue_metric",
          start_date: "",
          end_date: "",
          currency: "USD",
          value: 0,
          revenue_type: "revenue",
        },
      },
      { timeZone: "Pacific/Auckland" },
    );
    await revenuecat.fetchMetric(ctx, creds, { ...request, comparePrevious: false });
    const params = new URL(scalar(ctx.calls[0])).searchParams;
    // Midnight UTC on 5 October is already the afternoon of the 5th in
    // Auckland; midnight UTC on 5 September is the 5th there too.
    expect(params.get("start_date")).toBe("2026-09-05");
    expect(params.get("end_date")).toBe("2026-10-05");
  });
});

describe("revenuecat verify", () => {
  it("names the connection after the project and records the currency", async () => {
    const ctx = stubContext({ "/v2/projects?": projects, "/metrics/overview": overview("GBP") });
    const result = await revenuecat.verify(ctx, { ...creds, project_id: undefined });
    expect(result.accountLabel).toBe("MagicWeather");
    expect(result.currency).toBe("GBP");
    expect(result.availableMetrics).toContain("mrr");
    expect(result.availableMetrics).toContain("revenue");
  });

  it("refuses to guess between several projects", async () => {
    const ctx = stubContext({
      "/v2/projects?": {
        ...projects,
        items: [
          ...projects.items,
          { object: "project", id: "proj2", name: "MagicNews", created_at: 2 },
        ],
      },
      "/metrics/overview": overview(),
    });
    await expect(revenuecat.verify(ctx, { ...creds, project_id: undefined })).rejects.toMatchObject(
      { code: "unsupported", message: expect.stringContaining("MagicNews") },
    );
  });

  it("rejects a project the key cannot see, rather than reporting an empty one", async () => {
    const ctx = stubContext({ "/v2/projects?": projects, "/metrics/overview": overview() });
    await expect(revenuecat.verify(ctx, { ...creds, project_id: "proj9" })).rejects.toMatchObject({
      code: "unsupported",
    });
  });

  it("accepts a charts-only key when the project id is typed", async () => {
    // The least-privilege key for our metrics cannot list projects. That
    // must be a working connection with a plainer label, not a rejection.
    const ctx = stubContext({
      "/v2/projects?": { __status: 403 },
      "/metrics/overview": overview(),
    });
    const result = await revenuecat.verify(ctx, creds);
    expect(result.accountLabel).toBe("Project proj1");
  });

  it("asks for the project id when a charts-only key has none", async () => {
    const ctx = stubContext({ "/v2/projects?": { __status: 403 } });
    await expect(revenuecat.verify(ctx, { ...creds, project_id: undefined })).rejects.toMatchObject(
      { code: "unsupported", message: expect.stringContaining("project ID") },
    );
  });

  it("fails the connection when the key cannot read the overview", async () => {
    // Every metric here needs charts_metrics:overview:read; a key without it
    // must not become a row that fails on its first poll.
    const ctx = stubContext({ "/v2/projects?": projects, "/metrics/overview": { __status: 403 } });
    await expect(revenuecat.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("maps 401 to auth_failed so polling stops", async () => {
    const ctx = stubContext({ "/v2/projects?": { __status: 401 } });
    await expect(revenuecat.verify(ctx, { ...creds, project_id: undefined })).rejects.toMatchObject(
      { code: "auth_failed" },
    );
  });

  it("does not mistake a bad key for a charts-only one just because a project id was typed", async () => {
    // 401 is "who are you", 403 is "not allowed". Only the second gets the
    // typed-id fallback; the first must be reported as the wrong key.
    const ctx = stubContext({ "/v2/projects?": { __status: 401 } });
    await expect(revenuecat.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("sends the key as a Bearer token", async () => {
    // v2 rejects a bare key with a 401 that looks like a wrong key.
    let seen: Record<string, string> | undefined;
    const ctx = stubContext({ "/v2/projects?": projects, "/metrics/overview": overview() });
    const original = ctx.http;
    ctx.http = (url: string, init?: RequestInit) => {
      seen ??= init?.headers as Record<string, string> | undefined;
      return original(url, init);
    };
    await revenuecat.verify(ctx, creds);
    expect(seen).toMatchObject({ authorization: `Bearer ${creds.secret_key}` });
  });

  it("treats an empty project id field as not provided", () => {
    const parsed = revenuecat.credentialSchema.parse({ ...creds, project_id: "" });
    expect(parsed.project_id).toBeUndefined();
  });
});
