import { describe, expect, it } from "vitest";
import { dodopayments } from "../src/providers/dodopayments/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { api_key: "dodo_test_abcdefghijklmnopqrst", mode: "live" as const };

const request = {
  metric: "mrr" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
};

function sub(options: { amount: number; interval?: string; count?: number; currency?: string }) {
  return {
    subscription_id: `sub_${options.amount}_${options.interval ?? "Month"}`,
    status: "active",
    recurring_pre_tax_amount: options.amount,
    currency: options.currency ?? "USD",
    payment_frequency_interval: options.interval ?? "Month",
    payment_frequency_count: options.count ?? 1,
    created_at: "2026-01-01T00:00:00Z",
  };
}

function payment(options: { amount: number; at: string; status?: string; currency?: string }) {
  return {
    payment_id: `pay_${options.at}`,
    total_amount: options.amount,
    currency: options.currency ?? "USD",
    status: options.status ?? "succeeded",
    created_at: options.at,
  };
}

describe("dodo payments MRR", () => {
  it("normalises an annual plan to a twelfth of its price", async () => {
    const ctx = stubContext({
      "/subscriptions": { items: [sub({ amount: 120_000, interval: "Year" })] },
    });
    // $1,200/year is $100/month.
    expect((await dodopayments.fetchMetric(ctx, creds, request)).value).toBe(10_000);
  });

  it("accepts Dodo's capitalised intervals", async () => {
    // The API sends "Month", `toMonthly` matches on "month". Getting this
    // wrong falls through to the default branch and silently reports a
    // yearly plan as if it were monthly.
    const ctx = stubContext({
      "/subscriptions": { items: [sub({ amount: 5_000, interval: "Month" })] },
    });
    expect((await dodopayments.fetchMetric(ctx, creds, request)).value).toBe(5_000);
  });

  it("divides by the frequency count", async () => {
    const ctx = stubContext({
      "/subscriptions": { items: [sub({ amount: 30_000, interval: "Month", count: 3 })] },
    });
    expect((await dodopayments.fetchMetric(ctx, creds, request)).value).toBe(10_000);
  });

  it("excludes other currencies and says so", async () => {
    const ctx = stubContext({
      "/subscriptions": {
        items: [sub({ amount: 5_000 }), sub({ amount: 9_000, currency: "EUR" })],
      },
    });
    const series = await dodopayments.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(5_000);
    expect(series.note).toContain("EUR");
  });

  it("is a snapshot, not a sum of its points", async () => {
    const ctx = stubContext({ "/subscriptions": { items: [sub({ amount: 7_000 })] } });
    const series = await dodopayments.fetchMetric(ctx, creds, request);
    expect(series.points).toHaveLength(1);
    expect(series.value).toBe(7_000);
  });
});

describe("dodo payments revenue", () => {
  const revenueRequest = { ...request, metric: "revenue" as const };

  it("counts only succeeded payments", async () => {
    const ctx = stubContext({
      "/payments": {
        items: [
          payment({ amount: 1_000, at: "2026-09-10T10:00:00Z" }),
          payment({ amount: 9_999, at: "2026-09-11T10:00:00Z", status: "processing" }),
          payment({ amount: 2_000, at: "2026-09-12T10:00:00Z" }),
        ],
      },
    });
    expect((await dodopayments.fetchMetric(ctx, creds, revenueRequest)).value).toBe(3_000);
  });

  it("gap-fills quiet days so a sparkline is not compressed", async () => {
    const ctx = stubContext({
      "/payments": { items: [payment({ amount: 500, at: "2026-09-10T10:00:00Z" })] },
    });
    const series = await dodopayments.fetchMetric(ctx, creds, revenueRequest);
    expect(series.points.length).toBeGreaterThan(25);
    expect(series.points.filter((p) => p.v === 0).length).toBeGreaterThan(20);
  });

  it("keeps the comparison window out of the headline figure", async () => {
    const ctx = stubContext({
      "/payments": {
        items: [
          payment({ amount: 400, at: "2026-08-10T10:00:00Z" }),
          payment({ amount: 1_000, at: "2026-09-20T10:00:00Z" }),
        ],
      },
    });
    const series = await dodopayments.fetchMetric(ctx, creds, {
      ...revenueRequest,
      comparePrevious: true,
    });
    expect(series.value).toBe(1_000);
    expect(series.previousValue).toBe(400);
  });
});

describe("dodo payments pagination", () => {
  it("stops on a short page rather than waiting for a cursor", async () => {
    // Dodo sends no cursor and no has_more. A walk waiting for one is an
    // infinite loop inside a Worker.
    const ctx = stubContext({
      "/subscriptions": (url: URL) => {
        const page = Number(url.searchParams.get("page_number"));
        if (page === 0) return { items: Array.from({ length: 100 }, () => sub({ amount: 100 })) };
        if (page === 1) return { items: [sub({ amount: 100 })] };
        throw new Error("walked past the short page");
      },
    });
    expect((await dodopayments.fetchMetric(ctx, creds, request)).value).toBe(10_100);
  });
});

describe("dodo payments verify", () => {
  it("offers everything to a key that can read both lists", async () => {
    const ctx = stubContext({
      "/payments": { items: [] },
      "/subscriptions": { items: [sub({ amount: 100, currency: "EUR" })] },
    });
    const result = await dodopayments.verify(ctx, creds);
    expect(result.availableMetrics).toEqual([
      "revenue",
      "recent_payments",
      "mrr",
      "active_subscribers",
    ]);
    expect(result.currency).toBe("EUR");
  });

  it("narrows to revenue and payments when the key lacks subscriptions:read", async () => {
    // The real case: a live key scoped to payments and refunds. Dodo answers
    // 403 INSUFFICIENT_PERMISSION on /subscriptions, which used to be
    // reported as a bad key.
    const ctx = stubContext({
      "/payments": {
        items: [
          {
            payment_id: "p",
            total_amount: 1,
            currency: "usd",
            status: "succeeded",
            created_at: "2026-10-01T00:00:00Z",
          },
        ],
      },
      "/subscriptions": { __status: 403 },
    });
    const result = await dodopayments.verify(ctx, creds);
    expect(result.availableMetrics).toEqual(["revenue", "recent_payments"]);
    expect(result.currency).toBe("USD");
  });

  it("rejects a key that can read nothing, naming the scopes", async () => {
    const ctx = stubContext({
      "/payments": { __status: 403 },
      "/subscriptions": { __status: 403 },
    });
    await expect(dodopayments.verify(ctx, creds)).rejects.toMatchObject({
      code: "unsupported",
      message: expect.stringContaining("subscriptions:read"),
    });
  });
});

describe("dodo payments errors", () => {
  it("maps 401 to auth_failed so polling stops", async () => {
    const ctx = stubContext({ "/payments": { __status: 401 } });
    await expect(dodopayments.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("carries Retry-After through a 429", async () => {
    const ctx = stubContext({
      "/payments": { __status: 429, __headers: { "retry-after": "30" } },
    });
    await expect(dodopayments.verify(ctx, creds)).rejects.toMatchObject({
      code: "rate_limited",
      retryAfterSeconds: 30,
    });
  });

  it("refuses a metric it does not provide", async () => {
    const ctx = stubContext({});
    await expect(
      dodopayments.fetchMetric(ctx, creds, { ...request, metric: "backlinks" }),
    ).rejects.toBeInstanceOf(ProviderError);
  });
});

describe("dodo payments host selection", () => {
  it("sends a test-mode key to the test host", async () => {
    const ctx = stubContext({ "/payments": { items: [] }, "/subscriptions": { items: [] } });
    await dodopayments.verify(ctx, { ...creds, mode: "test" });
    expect(ctx.calls[0]).toContain("test.dodopayments.com");
  });

  it("sends a live-mode key to the live host", async () => {
    const ctx = stubContext({ "/payments": { items: [] }, "/subscriptions": { items: [] } });
    await dodopayments.verify(ctx, creds);
    expect(ctx.calls[0]).toContain("live.dodopayments.com");
  });
});

describe("dodo recent payments", () => {
  it("lists succeeded payments with the customer", async () => {
    const ctx = stubContext({
      "/payments": {
        items: [
          {
            payment_id: "p1",
            total_amount: 1_900,
            currency: "USD",
            status: "succeeded",
            created_at: "2026-10-05T10:00:00Z",
            customer: { name: "Ada", email: "ada@example.com" },
          },
          {
            payment_id: "p2",
            total_amount: 1_900,
            currency: "USD",
            status: "processing",
            created_at: "2026-10-04T10:00:00Z",
          },
        ],
      },
    });
    const series = await dodopayments.fetchMetric(ctx, creds, {
      ...request,
      metric: "recent_payments",
    });
    expect(series.items?.map((i) => i.id)).toEqual(["p1"]);
    expect(scalar(series.items?.[0]).label).toBe("Ada");
    expect(series.value).toBe(1_900);
  });
});
