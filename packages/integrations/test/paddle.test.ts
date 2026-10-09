import { describe, expect, it } from "vitest";
import { paddle } from "../src/providers/paddle/index.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = {
  api_key: "pdl_live_apikey_01gtgztp8f4kek3yd4g1wrksa3_q6TGTJyvoIz7LDtXT65bX7_AQO",
  mode: "live" as const,
};

const request = {
  metric: "mrr" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

function page<T>(data: T[], next?: string) {
  return {
    data,
    meta: { pagination: { per_page: data.length, has_more: Boolean(next), next: next ?? null } },
  };
}

function subscription(options: {
  id: string;
  amount: string;
  interval?: string;
  frequency?: number;
  quantity?: number;
  currency?: string;
  status?: string;
  itemStatus?: string;
  startedAt?: string;
  canceledAt?: string | null;
}) {
  return {
    id: options.id,
    status: options.status ?? "active",
    currency_code: options.currency ?? "USD",
    created_at: options.startedAt ?? "2026-01-01T00:00:00Z",
    started_at: options.startedAt ?? "2026-01-01T00:00:00Z",
    canceled_at: options.canceledAt ?? null,
    items: [
      {
        status: options.itemStatus ?? "active",
        quantity: options.quantity ?? 1,
        recurring: true,
        price: {
          unit_price: { amount: options.amount, currency_code: options.currency ?? "USD" },
          billing_cycle: {
            interval: options.interval ?? "month",
            frequency: options.frequency ?? 1,
          },
        },
      },
    ],
  };
}

function transaction(options: {
  id: string;
  total: string;
  billedAt: string;
  status?: string;
  currency?: string;
  name?: string | null;
  email?: string | null;
  product?: string;
}) {
  return {
    id: options.id,
    status: options.status ?? "completed",
    currency_code: options.currency ?? "USD",
    billed_at: options.billedAt,
    created_at: options.billedAt,
    customer: { name: options.name ?? null, email: options.email ?? null },
    details: {
      totals: { total: options.total },
      line_items: options.product ? [{ product: { name: options.product } }] : [],
    },
  };
}

describe("paddle MRR", () => {
  it("parses string minor units and normalises a yearly plan with quantity", async () => {
    const ctx = stubContext({
      "/subscriptions": page([
        subscription({ id: "s1", amount: "120000", interval: "year", quantity: 2 }),
        subscription({ id: "s2", amount: "2500" }),
      ]),
    });
    const series = await paddle.fetchMetric(ctx, creds, request);
    // $1,200/year × 2 seats = $200/month, plus $25.
    expect(series.value).toBe(22_500);
    expect(series.currency).toBe("USD");
  });

  it("excludes other currencies and says so", async () => {
    const ctx = stubContext({
      "/subscriptions": page([
        subscription({ id: "s1", amount: "1000" }),
        subscription({ id: "s2", amount: "9000", currency: "GBP" }),
      ]),
    });
    const series = await paddle.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(1_000);
    expect(series.note).toContain("GBP");
  });

  it("skips an inactive item on an active subscription", async () => {
    const ctx = stubContext({
      "/subscriptions": page([subscription({ id: "s1", amount: "1000", itemStatus: "inactive" })]),
    });
    expect((await paddle.fetchMetric(ctx, creds, request)).value).toBe(0);
  });

  it("refuses a non-integer amount rather than rounding it", async () => {
    const ctx = stubContext({
      "/subscriptions": page([subscription({ id: "s1", amount: "10.00" })]),
    });
    await expect(paddle.fetchMetric(ctx, creds, request)).rejects.toMatchObject({
      code: "bad_response",
    });
  });

  it("follows the next link Paddle sends until has_more is false", async () => {
    const ctx = stubContext({
      "/subscriptions": (url: URL) =>
        url.searchParams.get("after") === "s1"
          ? page([subscription({ id: "s2", amount: "1000" })])
          : page(
              [subscription({ id: "s1", amount: "1000" })],
              "https://api.paddle.com/subscriptions?status=active&per_page=200&after=s1",
            ),
    });
    const series = await paddle.fetchMetric(ctx, creds, {
      ...request,
      metric: "active_subscribers",
    });
    expect(series.value).toBe(2);
    expect(ctx.calls).toHaveLength(2);
  });
});

describe("paddle revenue", () => {
  const revenueRequest = { ...request, metric: "revenue" as const, comparePrevious: true };

  it("totals paid transactions by billing date and splits the previous window", async () => {
    const ctx = stubContext({
      "/transactions": (url: URL) => {
        expect(url.searchParams.get("status")).toBe("paid,completed");
        expect(url.searchParams.get("billed_at[GTE]")).toBe("2026-08-06T00:00:00Z");
        expect(url.searchParams.get("billed_at[LTE]")).toBe("2026-10-05T00:00:00Z");
        return page([
          transaction({ id: "t1", total: "5000", billedAt: "2026-10-01T10:00:00Z" }),
          transaction({
            id: "t2",
            total: "3000",
            billedAt: "2026-09-20T10:00:00Z",
            status: "paid",
          }),
          transaction({ id: "t3", total: "7000", billedAt: "2026-08-20T10:00:00Z" }),
          transaction({
            id: "t4",
            total: "9000",
            billedAt: "2026-09-21T10:00:00Z",
            currency: "EUR",
          }),
        ]);
      },
    });
    const series = await paddle.fetchMetric(ctx, creds, revenueRequest);
    expect(series.value).toBe(8_000);
    expect(series.previousValue).toBe(7_000);
    expect(series.note).toContain("EUR");
    expect(series.points.length).toBeGreaterThan(1);
  });
});

describe("paddle subscription events", () => {
  it("counts starts in the window from the whole book", async () => {
    const ctx = stubContext({
      "/subscriptions": page([
        subscription({ id: "s1", amount: "1000", startedAt: "2026-09-10T00:00:00Z" }),
        subscription({ id: "s2", amount: "1000", startedAt: "2026-08-10T00:00:00Z" }),
        subscription({
          id: "s3",
          amount: "1000",
          startedAt: "2026-09-30T00:00:00Z",
          status: "canceled",
        }),
      ]),
    });
    const series = await paddle.fetchMetric(ctx, creds, {
      ...request,
      metric: "new_subscribers",
      comparePrevious: true,
    });
    expect(series.value).toBe(2);
    expect(series.previousValue).toBe(1);
  });

  it("counts cancellations by canceled_at", async () => {
    const ctx = stubContext({
      "/subscriptions": (url: URL) => {
        expect(url.searchParams.get("status")).toBe("canceled");
        return page([
          subscription({
            id: "s1",
            amount: "1000",
            status: "canceled",
            canceledAt: "2026-09-12T00:00:00Z",
          }),
        ]);
      },
    });
    const series = await paddle.fetchMetric(ctx, creds, {
      ...request,
      metric: "churned_subscribers",
    });
    expect(series.value).toBe(1);
  });
});

describe("paddle recent payments", () => {
  it("lists transactions with the embedded customer and the first product", async () => {
    const ctx = stubContext({
      "/transactions": (url: URL) => {
        expect(url.searchParams.get("include")).toBe("customer");
        expect(url.searchParams.get("order_by")).toBe("billed_at[DESC]");
        return page([
          transaction({
            id: "t1",
            total: "5000",
            billedAt: "2026-10-01T10:00:00Z",
            name: "Ada",
            product: "Pro",
          }),
          transaction({
            id: "t2",
            total: "3000",
            billedAt: "2026-09-20T10:00:00Z",
            email: "grace@example.com",
          }),
        ]);
      },
    });
    const series = await paddle.fetchMetric(ctx, creds, { ...request, metric: "recent_payments" });
    const items = series.items ?? [];
    expect(items).toHaveLength(2);
    expect(scalar(items[0]).label).toBe("Ada");
    expect(scalar(items[0]).detail).toBe("Pro");
    expect(scalar(items[0]).amount).toBe(5_000);
    expect(scalar(items[1]).label).toBe("grace@example.com");
    expect(series.value).toBe(8_000);
  });
});

describe("paddle verify", () => {
  it("offers everything to a key that can read both, labelled by environment only", async () => {
    const ctx = stubContext({
      "/event-types": { data: [] },
      "/transactions": page([
        transaction({ id: "t1", total: "1", billedAt: "2026-10-01T00:00:00Z", currency: "GBP" }),
      ]),
      "/subscriptions": page([]),
    });
    const result = await paddle.verify(ctx, { ...creds, mode: "sandbox" });
    expect(result.accountLabel).toBe("Sandbox");
    expect(result.currency).toBe("GBP");
    expect(result.availableMetrics).toContain("mrr");
    expect(result.availableMetrics).toContain("recent_payments");
    expect(scalar(ctx.calls[0])).toMatch(/^https:\/\/sandbox-api\.paddle\.com\//);
  });

  it("has no label on live, since Paddle never names the seller", async () => {
    const ctx = stubContext({
      "/event-types": { data: [] },
      "/transactions": page([]),
      "/subscriptions": page([]),
    });
    expect((await paddle.verify(ctx, creds)).accountLabel).toBeNull();
  });

  it("narrows to transactions when the key cannot read subscriptions", async () => {
    const ctx = stubContext({
      "/event-types": { data: [] },
      "/transactions": page([]),
      "/subscriptions": { __status: 403 },
    });
    const result = await paddle.verify(ctx, creds);
    expect(result.availableMetrics).toEqual(["revenue", "recent_payments"]);
  });

  it("treats 403 on the first call as a bad key, since Paddle never answers 401", async () => {
    const ctx = stubContext({ "/event-types": { __status: 403 } });
    await expect(paddle.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("pins the API version on every call", async () => {
    let seen: Record<string, string> | undefined;
    const ctx = stubContext({
      "/event-types": { data: [] },
      "/transactions": page([]),
      "/subscriptions": page([]),
    });
    const original = ctx.http;
    ctx.http = (url: string, init?: RequestInit) => {
      seen ??= init?.headers as Record<string, string> | undefined;
      return original(url, init);
    };
    await paddle.verify(ctx, creds);
    expect(seen).toMatchObject({ "paddle-version": "1" });
  });
});
