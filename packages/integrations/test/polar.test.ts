import { describe, expect, it } from "vitest";
import { polar } from "../src/providers/polar/index.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = {
  access_token: "polar_oat_abcdefghijklmnopqrstuvwxyz0123456789",
  mode: "production" as const,
};

const org = {
  items: [{ id: "org_1", name: "Acme", slug: "acme", default_presentment_currency: "eur" }],
  pagination: { total_count: 1, max_page: 1 },
};

const request = {
  metric: "revenue" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
};

function period(day: string, values: Record<string, number | null>) {
  return { timestamp: `2026-${day}T00:00:00.000000Z`, ...values };
}

describe("polar windowed metrics", () => {
  it("asks for both windows in one call and splits them by timestamp", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/": (url: URL) => {
        expect(url.searchParams.get("start_date")).toBe("2026-09-27");
        expect(url.searchParams.get("end_date")).toBe("2026-10-05");
        expect(url.searchParams.get("interval")).toBe("day");
        expect(url.searchParams.get("metrics")).toBe("revenue");
        return {
          periods: [
            period("09-28", { revenue: 1_000 }),
            period("09-30", { revenue: 2_000 }),
            period("10-01", { revenue: 5_000 }),
            period("10-03", { revenue: 7_000 }),
            period("10-05", { revenue: null }),
          ],
        };
      },
    });
    const series = await polar.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(12_000);
    expect(series.previousValue).toBe(3_000);
    expect(series.points).toHaveLength(3);
    // The organization's currency, uppercased: Polar's metrics carry none.
    expect(series.currency).toBe("EUR");
  });

  it("counts subscriptions without a currency", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/": { periods: [period("10-02", { new_subscriptions: 3 })] },
    });
    const series = await polar.fetchMetric(ctx, creds, { ...request, metric: "new_subscribers" });
    expect(series.unit).toBe("count");
    expect(series.currency).toBeNull();
    expect(series.value).toBe(3);
  });

  it("uses the hour interval when asked for one", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/": (url: URL) => {
        expect(url.searchParams.get("interval")).toBe("hour");
        return { periods: [] };
      },
    });
    await polar.fetchMetric(ctx, creds, { ...request, granularity: "hour" });
  });
});

describe("polar snapshots", () => {
  it("takes the last day Polar has computed, not the last day listed", async () => {
    // Polar's pipeline lags: today's MRR is null until it runs. Reading the
    // last period literally shows zero at midnight.
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/": {
        periods: [
          period("10-03", { monthly_recurring_revenue: 80_000 }),
          period("10-04", { monthly_recurring_revenue: 81_500 }),
          period("10-05", { monthly_recurring_revenue: null }),
        ],
      },
    });
    const series = await polar.fetchMetric(ctx, creds, { ...request, metric: "mrr" });
    expect(series.value).toBe(81_500);
    expect(series.points).toHaveLength(1);
    expect(series.previousValue).toBeNull();
    expect(series.asOf?.toISOString()).toBe("2026-10-04T00:00:00.000Z");
  });

  it("asks for a week of days whatever the widget's range is", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/": (url: URL) => {
        expect(url.searchParams.get("interval")).toBe("day");
        expect(url.searchParams.get("start_date")).toBe("2026-09-28");
        return { periods: [period("10-05", { active_subscriptions: 42 })] };
      },
    });
    const series = await polar.fetchMetric(ctx, creds, {
      ...request,
      metric: "active_subscribers",
      granularity: "month",
    });
    expect(series.value).toBe(42);
  });
});

describe("polar recent payments", () => {
  it("lists paid orders newest first with the customer and product", async () => {
    const ctx = stubContext({
      "/v1/orders/": (url: URL) => {
        expect(url.searchParams.get("sorting")).toBe("-created_at");
        return {
          items: [
            {
              id: "o1",
              created_at: "2026-10-05T10:00:00Z",
              status: "paid",
              total_amount: 2_900,
              currency: "usd",
              customer: { name: "Ada", email: "ada@example.com" },
              product: { name: "Pro" },
            },
            {
              id: "o2",
              created_at: "2026-10-04T10:00:00Z",
              status: "pending",
              total_amount: 9_900,
              currency: "usd",
              customer: null,
            },
            {
              id: "o3",
              created_at: "2026-10-03T10:00:00Z",
              status: "partially_refunded",
              total_amount: 1_000,
              currency: "usd",
              customer: { name: null, email: "grace@example.com" },
              product: null,
              description: "Starter",
            },
          ],
        };
      },
    });
    const series = await polar.fetchMetric(ctx, creds, { ...request, metric: "recent_payments" });
    const items = series.items ?? [];
    expect(items.map((i) => i.id)).toEqual(["o1", "o3"]);
    expect(scalar(items[0]).label).toBe("Ada");
    expect(scalar(items[0]).detail).toBe("Pro");
    expect(scalar(items[1]).label).toBe("grace@example.com");
    expect(scalar(items[1]).detail).toBe("Starter");
    expect(scalar(items[1]).status).toBe("partially refunded");
    expect(series.value).toBe(3_900);
  });
});

describe("polar verify", () => {
  it("names the connection after the organization and records its currency", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/limits": { min_date: "2020-01-01", intervals: {} },
      "/v1/orders/": { items: [] },
    });
    const result = await polar.verify(ctx, creds);
    expect(result.accountLabel).toBe("Acme");
    expect(result.currency).toBe("EUR");
    expect(result.availableMetrics).toContain("mrr");
    expect(result.availableMetrics).toContain("recent_payments");
  });

  it("narrows to orders when the token lacks metrics:read", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/limits": { __status: 403 },
      "/v1/orders/": { items: [] },
    });
    const result = await polar.verify(ctx, creds);
    expect(result.availableMetrics).toEqual(["recent_payments"]);
  });

  it("rejects a token that can read nothing useful", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/limits": { __status: 403 },
      "/v1/orders/": { __status: 403 },
    });
    await expect(polar.verify(ctx, creds)).rejects.toMatchObject({ code: "unsupported" });
  });

  it("maps 401 to auth_failed so polling stops", async () => {
    const ctx = stubContext({ "/v1/organizations/": { __status: 401 } });
    await expect(polar.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("talks to the sandbox host when told to", async () => {
    const ctx = stubContext({
      "/v1/organizations/": org,
      "/v1/metrics/limits": {},
      "/v1/orders/": { items: [] },
    });
    await polar.verify(ctx, { ...creds, mode: "sandbox" });
    expect(scalar(ctx.calls[0])).toMatch(/^https:\/\/sandbox-api\.polar\.sh\//);
  });
});
