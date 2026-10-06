import { describe, expect, it } from "vitest";
import { lemonsqueezy } from "../src/providers/lemonsqueezy/index.ts";
import { stubContext } from "./helpers.ts";

const creds = { api_key: "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9abc", store_id: undefined };

const request = {
  metric: "mrr" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
};

function subscription(priceId: number, quantity = 1, status = "active") {
  return {
    id: `${priceId}-${quantity}`,
    attributes: {
      store_id: 1,
      status,
      created_at: "2026-01-01T00:00:00Z",
      first_subscription_item: { price_id: priceId, quantity },
    },
  };
}

function price(unitPrice: number, unit: string | null = "month", quantity = 1) {
  return {
    data: {
      id: "p",
      attributes: {
        unit_price: unitPrice,
        category: unit === null ? "one_time" : "subscription",
        renewal_interval_unit: unit,
        renewal_interval_quantity: quantity,
      },
    },
  };
}

function order(options: {
  total: number;
  at: string;
  status?: string;
  currency?: string;
  refunded?: number;
}) {
  return {
    id: options.at,
    attributes: {
      store_id: 1,
      currency: options.currency ?? "USD",
      total: options.total,
      status: options.status ?? "paid",
      refunded: (options.refunded ?? 0) > 0,
      refunded_amount: options.refunded ?? 0,
      created_at: options.at,
    },
  };
}

describe("lemon squeezy MRR", () => {
  it("normalises an annual price to a twelfth", async () => {
    const ctx = stubContext({
      "/subscriptions": { data: [subscription(1)] },
      "/prices/1": price(120_000, "year"),
    });
    expect((await lemonsqueezy.fetchMetric(ctx, creds, request)).value).toBe(10_000);
  });

  it("multiplies by the subscription item quantity", async () => {
    const ctx = stubContext({
      "/subscriptions": { data: [subscription(1, 3)] },
      "/prices/1": price(1_000),
    });
    expect((await lemonsqueezy.fetchMetric(ctx, creds, request)).value).toBe(3_000);
  });

  it("fetches each distinct price once, not once per subscriber", async () => {
    // One request per subscription would exhaust a Worker's budget on a
    // mid-sized store, so the ids are deduplicated before fetching.
    const ctx = stubContext({
      "/subscriptions": { data: [subscription(1), subscription(1), subscription(1)] },
      "/prices/1": price(2_000),
    });
    const series = await lemonsqueezy.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(6_000);
    expect(ctx.calls.filter((url) => url.includes("/prices/1"))).toHaveLength(1);
  });

  it("excludes a one-time price and says how many", async () => {
    const ctx = stubContext({
      "/subscriptions": { data: [subscription(1), subscription(2)] },
      "/prices/1": price(2_000),
      "/prices/2": price(9_999, null),
    });
    const series = await lemonsqueezy.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(2_000);
    expect(series.note).toContain("1 subscription");
  });
});

describe("lemon squeezy revenue", () => {
  const revenueRequest = { ...request, metric: "revenue" as const };

  it("counts orders that took payment and ignores those that did not", async () => {
    const ctx = stubContext({
      "/orders": {
        data: [
          order({ total: 1_000, at: "2026-09-20T10:00:00Z" }),
          order({ total: 5_000, at: "2026-09-19T10:00:00Z", status: "pending" }),
          order({ total: 2_000, at: "2026-09-18T10:00:00Z", status: "partial_refund" }),
          order({ total: 7_000, at: "2026-09-17T10:00:00Z", status: "failed" }),
        ],
      },
    });
    expect((await lemonsqueezy.fetchMetric(ctx, creds, revenueRequest)).value).toBe(3_000);
  });

  it("keeps a later-refunded order in the day it was paid", async () => {
    // Gross. Refunds are their own metric; netting them off the original day
    // would make a past day's revenue change retroactively.
    const ctx = stubContext({
      "/orders": {
        data: [
          order({ total: 4_000, at: "2026-09-20T10:00:00Z", status: "refunded", refunded: 4_000 }),
        ],
      },
    });
    expect((await lemonsqueezy.fetchMetric(ctx, creds, revenueRequest)).value).toBe(4_000);
  });

  it("reports refunds separately from the same orders", async () => {
    const ctx = stubContext({
      "/orders": {
        data: [
          order({
            total: 4_000,
            at: "2026-09-20T10:00:00Z",
            status: "partial_refund",
            refunded: 1_500,
          }),
          order({ total: 1_000, at: "2026-09-19T10:00:00Z" }),
        ],
      },
    });
    const series = await lemonsqueezy.fetchMetric(ctx, creds, {
      ...request,
      metric: "refunds" as const,
    });
    expect(series.value).toBe(1_500);
  });

  it("stops walking at the first order older than the window", async () => {
    // Lemon Squeezy cannot filter orders by date but returns them newest
    // first, so the walk must not read the store's whole history.
    const ctx = stubContext({
      "/orders": (url: URL) => {
        const page = Number(url.searchParams.get("page[number]"));
        if (page === 1) {
          return {
            data: [
              ...Array.from({ length: 99 }, (_, i) =>
                order({
                  total: 100,
                  at: `2026-09-${String(10 + (i % 20)).padStart(2, "0")}T10:00:00Z`,
                }),
              ),
              order({ total: 100, at: "2020-01-01T10:00:00Z" }),
            ],
          };
        }
        throw new Error("walked past the end of the window");
      },
    });
    const series = await lemonsqueezy.fetchMetric(ctx, creds, revenueRequest);
    expect(series.value).toBe(9_900);
  });

  it("excludes other currencies and says so", async () => {
    const ctx = stubContext({
      "/orders": {
        data: [
          order({ total: 1_000, at: "2026-09-20T10:00:00Z" }),
          order({ total: 8_000, at: "2026-09-19T10:00:00Z", currency: "GBP" }),
        ],
      },
    });
    const series = await lemonsqueezy.fetchMetric(ctx, creds, revenueRequest);
    expect(series.value).toBe(1_000);
    expect(series.note).toContain("GBP");
  });
});

describe("lemon squeezy verify", () => {
  it("labels the connection with the store when one is named", async () => {
    const ctx = stubContext({
      "/users/me": { data: { id: "1", attributes: { name: "Ada", email: "ada@example.com" } } },
      "/stores": { data: [{ id: "42", attributes: { name: "Widgets Inc", currency: "USD" } }] },
    });
    const result = await lemonsqueezy.verify(ctx, { ...creds, store_id: "42" });
    expect(result.accountLabel).toBe("Widgets Inc");
    expect(result.currency).toBe("USD");
  });

  it("rejects a store the key cannot see, rather than reporting an empty one", async () => {
    const ctx = stubContext({
      "/users/me": { data: { id: "1", attributes: { name: "Ada" } } },
      "/stores": { data: [{ id: "42", attributes: { name: "Widgets Inc", currency: "USD" } }] },
    });
    await expect(lemonsqueezy.verify(ctx, { ...creds, store_id: "99" })).rejects.toMatchObject({
      code: "unsupported",
    });
  });

  it("maps 401 to auth_failed so polling stops", async () => {
    const ctx = stubContext({ "/users/me": { __status: 401 } });
    await expect(lemonsqueezy.verify(ctx, creds)).rejects.toMatchObject({ code: "auth_failed" });
  });

  it("sends the JSON:API Accept header", async () => {
    // Without it Lemon Squeezy answers 406, which reads as a routing problem.
    let seen: Record<string, string> | undefined;
    const ctx = stubContext({
      "/users/me": { data: { id: "1", attributes: { name: "Ada" } } },
      "/stores": { data: [] },
    });
    const original = ctx.http;
    ctx.http = (url: string, init?: RequestInit) => {
      seen ??= init?.headers as Record<string, string> | undefined;
      return original(url, init);
    };
    await lemonsqueezy.verify(ctx, creds);
    expect(seen).toMatchObject({ accept: "application/vnd.api+json" });
  });
});
