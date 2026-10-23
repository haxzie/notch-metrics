import { describe, expect, it } from "vitest";
import { ProviderError } from "../src/types.ts";
import { credentialSchema, shopify } from "../src/providers/shopify/index.ts";
import { scalar, stubContext, expectMetrics } from "./helpers.ts";

const creds = {
  shop_domain: "acme-supply.myshopify.com",
  access_token: "shpat_0123456789abcdef0123456789abcdef",
};

const request = {
  metric: "revenue" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

function order(options: {
  at: string;
  total?: string;
  refunded?: string;
  currency?: string;
  status?: string;
  test?: boolean;
  customer?: { displayName?: string | null; email?: string | null } | null;
  product?: string;
}) {
  const currency = options.currency ?? "USD";
  const bag = (amount: string) => ({ shopMoney: { amount, currencyCode: currency } });
  return {
    id: `gid://shopify/Order/${options.at}`,
    name: `#10${options.at.slice(8, 10)}`,
    createdAt: options.at,
    test: options.test ?? false,
    displayFinancialStatus: options.status ?? "PAID",
    totalPriceSet: bag(options.total ?? "0.00"),
    totalRefundedSet: bag(options.refunded ?? "0.00"),
    customer:
      options.customer === undefined
        ? { displayName: "Ada", email: "ada@x.dev" }
        : options.customer,
    lineItems: { nodes: [{ title: options.product ?? "Desk mat" }] },
  };
}

/** One page, no cursor to follow. */
function ordersPage(nodes: unknown[]) {
  return { data: { orders: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } };
}

function verifyPayload(
  options: { orders?: boolean; customers?: boolean; name?: string | null } = {},
) {
  const errors: { message: string; extensions: { code: string } }[] = [];
  if (options.orders === false) {
    errors.push({
      message: "Access denied for ordersCount field. Required access: `read_orders`",
      extensions: { code: "ACCESS_DENIED" },
    });
  }
  if (options.customers === false) {
    errors.push({
      message: "Access denied for customersCount field. Required access: `read_customers`",
      extensions: { code: "ACCESS_DENIED" },
    });
  }
  return {
    data: {
      shop: {
        name: options.name === undefined ? "Acme Supply" : options.name,
        currencyCode: "USD",
        myshopifyDomain: "acme-supply.myshopify.com",
      },
      ordersCount: options.orders === false ? null : { count: 412 },
      customersCount: options.customers === false ? null : { count: 1_204 },
    },
    ...(errors.length ? { errors } : {}),
  };
}

describe("shopify credentials", () => {
  it("normalises whatever form of the domain was pasted", () => {
    for (const input of [
      "acme-supply",
      "ACME-Supply.myshopify.com",
      "https://acme-supply.myshopify.com/admin",
    ]) {
      const parsed = credentialSchema.parse({ ...creds, shop_domain: input });
      expect(parsed.shop_domain).toBe("acme-supply.myshopify.com");
    }
  });

  it("is idempotent, because it also parses the stored blob back out", () => {
    const once = credentialSchema.parse(creds).shop_domain;
    expect(credentialSchema.parse({ ...creds, shop_domain: once }).shop_domain).toBe(once);
  });

  it("rejects a custom storefront domain rather than rewriting it", () => {
    // The Admin API does not answer on one, and appending .myshopify.com to it
    // would fail later as a 404 that reads like a deleted store.
    expect(() => credentialSchema.parse({ ...creds, shop_domain: "shop.acme.com" })).toThrow();
  });

  it("rejects a token that is not an Admin API token", () => {
    expect(() => credentialSchema.parse({ ...creds, access_token: "sk_live_nope" })).toThrow();
  });
});

describe("shopify verify", () => {
  it("names the store and reports its currency", async () => {
    const ctx = stubContext({ NotchVerify: verifyPayload() });
    const result = await shopify.verify(ctx, creds);
    expect(result.accountLabel).toBe("Acme Supply");
    expect(result.currency).toBe("USD");
    expect(result.availableMetrics).toContain("revenue");
    expect(result.availableMetrics).toContain("customers");
  });

  it("narrows rather than failing when the token cannot read customers", async () => {
    const ctx = stubContext({ NotchVerify: verifyPayload({ customers: false }) });
    const result = await shopify.verify(ctx, creds);
    expect(result.availableMetrics).toContain("revenue");
    expect(result.availableMetrics).not.toContain("customers");
    expect(result.availableMetrics).not.toContain("new_customers");
  });

  it("rejects a token that can read neither", async () => {
    const ctx = stubContext({
      NotchVerify: verifyPayload({ orders: false, customers: false }),
    });
    await expect(shopify.verify(ctx, creds)).rejects.toThrow(/read_orders and read_customers/);
  });

  it("falls back to the store handle when the shop has no name", async () => {
    const ctx = stubContext({ NotchVerify: verifyPayload({ name: null }) });
    expect((await shopify.verify(ctx, creds)).accountLabel).toBe("acme-supply");
  });
});

describe("shopify sales", () => {
  it("totals paid orders in minor units", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T10:00:00Z", total: "19.99" }),
        order({ at: "2026-09-11T10:00:00Z", total: "120.50" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(14_049);
    expect(series.currency).toBe("USD");
    expect(series.unit).toBe("currency");
  });

  it("does not multiply a currency with no minor unit by a hundred", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T10:00:00Z", total: "4800", currency: "JPY" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(4_800);
    expect(series.currency).toBe("JPY");
  });

  it("reports the store's currency and says so when it is not the user's", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T10:00:00Z", total: "10.00", currency: "EUR" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(series.currency).toBe("EUR");
    expect(series.note).toMatch(/EUR/);
  });

  it("excludes test orders and orders that never took payment", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T10:00:00Z", total: "50.00" }),
        order({ at: "2026-09-11T10:00:00Z", total: "99.00", test: true }),
        order({ at: "2026-09-12T10:00:00Z", total: "99.00", status: "PENDING" }),
        order({ at: "2026-09-13T10:00:00Z", total: "99.00", status: "AUTHORIZED" }),
        order({ at: "2026-09-14T10:00:00Z", total: "99.00", status: "VOIDED" }),
      ]),
    });
    expect((await shopify.fetchMetric(ctx, creds, request)).value).toBe(5_000);
  });

  it("counts a refunded order's original total, because it was paid that day", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({
          at: "2026-09-10T10:00:00Z",
          total: "40.00",
          refunded: "40.00",
          status: "REFUNDED",
        }),
      ]),
    });
    expect((await shopify.fetchMetric(ctx, creds, request)).value).toBe(4_000);
  });

  it("buckets by day and fills the quiet ones", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T01:00:00Z", total: "10.00" }),
        order({ at: "2026-09-10T23:00:00Z", total: "5.00" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(series.points).toHaveLength(31);
    const tenth = scalar(
      series.points.find((point) => point.t.toISOString().startsWith("2026-09-10")),
      "the tenth",
    );
    expect(tenth.v).toBe(1_500);
    expect(series.points.filter((point) => point.v > 0)).toHaveLength(1);
  });

  it("splits the widened walk into this window and the one before it", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({ at: "2026-09-10T10:00:00Z", total: "30.00" }),
        // Inside the previous 30 days, which is what the widened query asked
        // for — it must not land in the current total.
        order({ at: "2026-08-20T10:00:00Z", total: "70.00" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      comparePrevious: true,
    });
    expect(series.value).toBe(3_000);
    expect(series.previousValue).toBe(7_000);
  });
});

describe("shopify orders and AOV", () => {
  const nodes = [
    order({ at: "2026-09-10T10:00:00Z", total: "100.00" }),
    order({ at: "2026-09-10T11:00:00Z", total: "300.00" }),
    order({ at: "2026-09-20T10:00:00Z", total: "20.00" }),
  ];

  it("counts orders rather than summing them", async () => {
    const ctx = stubContext({ NotchOrders: ordersPage(nodes) });
    const series = await shopify.fetchMetric(ctx, creds, { ...request, metric: "orders" });
    expect(series.unit).toBe("count");
    expect(series.currency).toBeNull();
    expect(series.value).toBe(3);
  });

  it("averages over the window, not over the points", async () => {
    const ctx = stubContext({ NotchOrders: ordersPage(nodes) });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "average_order_value",
    });
    // 42_000 minor units over three orders. The mean of the two non-empty
    // days would be 20_000/2 + 2_000/2 = 11_000, which is the bug this
    // asserts against.
    expect(series.value).toBe(14_000);
    const tenth = scalar(
      series.points.find((point) => point.t.toISOString().startsWith("2026-09-10")),
      "the tenth",
    );
    expect(tenth.v).toBe(20_000);
  });

  it("reads zero rather than NaN for a window with no orders", async () => {
    const ctx = stubContext({ NotchOrders: ordersPage([]) });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "average_order_value",
    });
    expect(series.value).toBe(0);
    expect(series.points.every((point) => point.v === 0)).toBe(true);
  });
});

describe("shopify refunds", () => {
  it("sums the refunded amount, not the order total", async () => {
    const ctx = stubContext({
      NotchOrders: ordersPage([
        order({
          at: "2026-09-10T10:00:00Z",
          total: "90.00",
          refunded: "15.00",
          status: "PARTIALLY_REFUNDED",
        }),
        order({ at: "2026-09-11T10:00:00Z", total: "40.00" }),
      ]),
    });
    const series = await shopify.fetchMetric(ctx, creds, { ...request, metric: "refunds" });
    expect(series.value).toBe(1_500);
  });
});

describe("shopify recent payments", () => {
  it("totals in the store's currency even when the account prefers another", async () => {
    const ctx = stubContext(
      {
        NotchRecentOrders: {
          data: {
            orders: {
              nodes: [
                order({ at: "2026-10-04T10:00:00Z", total: "25.00", currency: "EUR" }),
                order({ at: "2026-10-03T10:00:00Z", total: "75.00", currency: "EUR" }),
              ],
            },
          },
        },
      },
      { preferredCurrency: "USD" },
    );
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "recent_payments",
    });
    // Zero here would mean the shared helper filtered the store's own rows
    // out for not being USD.
    expect(series.value).toBe(10_000);
    expect(series.items).toHaveLength(2);
    expect(scalar(series.items?.[0], "the newest row").label).toBe("Ada");
  });

  it("labels a guest order with its order number", async () => {
    const ctx = stubContext({
      NotchRecentOrders: {
        data: {
          orders: {
            nodes: [order({ at: "2026-10-04T10:00:00Z", total: "25.00", customer: null })],
          },
        },
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "recent_payments",
    });
    expect(scalar(series.items?.[0], "the row").label).toBe("#1004");
    expect(scalar(series.items?.[0], "the row").detail).toBe("Desk mat");
  });

  it("drops unpaid orders from the feed", async () => {
    const ctx = stubContext({
      NotchRecentOrders: {
        data: {
          orders: {
            nodes: [
              order({ at: "2026-10-04T10:00:00Z", total: "25.00", status: "PENDING" }),
              order({ at: "2026-10-03T10:00:00Z", total: "75.00" }),
            ],
          },
        },
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "recent_payments",
    });
    expect(series.items).toHaveLength(1);
  });
});

describe("shopify customers", () => {
  it("counts the records created in the window", async () => {
    const ctx = stubContext({
      NotchCustomers: {
        data: {
          customers: {
            nodes: [
              { id: "1", createdAt: "2026-09-10T10:00:00Z" },
              { id: "2", createdAt: "2026-09-11T10:00:00Z" },
            ],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, { ...request, metric: "new_customers" });
    expect(series.value).toBe(2);
    expect(series.unit).toBe("count");
  });

  it("keeps the previous window out of the current count", async () => {
    const ctx = stubContext({
      NotchCustomers: {
        data: {
          customers: {
            nodes: [
              { id: "1", createdAt: "2026-09-10T10:00:00Z" },
              { id: "2", createdAt: "2026-08-10T10:00:00Z" },
            ],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, {
      ...request,
      metric: "new_customers",
      comparePrevious: true,
    });
    expect(series.value).toBe(1);
    expect(series.previousValue).toBe(1);
  });

  it("says when Shopify's total is a floor rather than a count", async () => {
    const ctx = stubContext({
      NotchCustomersTotal: { data: { customersCount: { count: 10_000, precision: "AT_LEAST" } } },
    });
    const series = await shopify.fetchMetric(ctx, creds, { ...request, metric: "customers" });
    expect(series.value).toBe(10_000);
    expect(series.note).toMatch(/floor/);
  });

  it("reports an exact total without a note", async () => {
    const ctx = stubContext({
      NotchCustomersTotal: { data: { customersCount: { count: 842, precision: "EXACT" } } },
    });
    const series = await shopify.fetchMetric(ctx, creds, { ...request, metric: "customers" });
    expect(series.value).toBe(842);
    expect(series.note).toBeUndefined();
  });
});

describe("shopify paging and failure", () => {
  it("follows the cursor and stops at the page cap with a note", async () => {
    // Every page claims another, so the walk ends on the cap rather than on
    // the data — which is the case the note exists for.
    const ctx = stubContext({
      NotchOrders: (_url: URL, init?: RequestInit) => {
        const sent = JSON.parse(String(init?.body ?? "{}")) as {
          variables: { after: string | null };
        };
        const day = (sent.variables.after ?? "0").length % 20;
        return {
          data: {
            orders: {
              nodes: [order({ at: "2026-09-10T10:00:00Z", total: "1.00" })],
              pageInfo: { hasNextPage: true, endCursor: `cursor-${day}-${Math.random()}` },
            },
          },
        };
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(ctx.calls).toHaveLength(5);
    expect(series.value).toBe(500);
    expect(series.note).toMatch(/undercount/);
  });

  it("asks the scheduler to wait when the first page is throttled", async () => {
    const ctx = stubContext({
      NotchOrders: {
        errors: [{ message: "Throttled", extensions: { code: "THROTTLED" } }],
        extensions: {
          cost: {
            requestedQueryCost: 602,
            throttleStatus: { currentlyAvailable: 102, restoreRate: 50 },
          },
        },
      },
    });
    const error = await shopify.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("rate_limited");
    expect((error as ProviderError).retryAfterSeconds).toBe(10);
  });

  it("reports a partial total with a note when a later page is throttled", async () => {
    let page = 0;
    const ctx = stubContext({
      NotchOrders: () => {
        page += 1;
        if (page === 1) {
          return {
            data: {
              orders: {
                nodes: [order({ at: "2026-09-10T10:00:00Z", total: "12.00" })],
                pageInfo: { hasNextPage: true, endCursor: "next" },
              },
            },
          };
        }
        return { errors: [{ message: "Throttled", extensions: { code: "THROTTLED" } }] };
      },
    });
    const series = await shopify.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(1_200);
    expect(series.note).toMatch(/rate limited/);
  });

  it("names the missing scope instead of saying the key is wrong", async () => {
    const ctx = stubContext({
      NotchOrders: {
        data: null,
        errors: [
          {
            message: "Access denied for orders field. Required access: `read_orders`",
            extensions: { code: "ACCESS_DENIED" },
          },
        ],
      },
    });
    const error = await shopify.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("auth_failed");
    expect((error as ProviderError).message).toMatch(/read_orders/);
  });

  it("calls a frozen store frozen rather than unauthorised", async () => {
    const ctx = stubContext({ NotchOrders: { __status: 402 } });
    const error = await shopify.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
    expect((error as ProviderError).message).toMatch(/frozen/);
  });

  it("reads a 404 as an uninstalled app, not a server fault", async () => {
    const ctx = stubContext({ NotchOrders: { __status: 404 } });
    const error = await shopify.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("auth_failed");
  });

  it("turns a throttle outside the order walk into a rate limit, not a crash", async () => {
    // Only the walk has a partial total to report. Anywhere else a throttle
    // has to leave the adapter as a ProviderError, or the tile renders
    // "something went wrong" over an Error nobody mapped.
    const throttled = {
      errors: [{ message: "Throttled", extensions: { code: "THROTTLED" } }],
    };
    const ctx = stubContext({ NotchVerify: throttled, NotchCustomersTotal: throttled });

    for (const run of [
      () => shopify.verify(ctx, creds),
      () => shopify.fetchMetric(ctx, creds, { ...request, metric: "customers" }),
    ]) {
      const error = await run().catch((e: unknown) => e);
      expect(error).toBeInstanceOf(ProviderError);
      expect((error as ProviderError).code).toBe("rate_limited");
    }
  });

  it("refuses a metric it does not offer", async () => {
    const ctx = stubContext({});
    await expect(shopify.fetchMetric(ctx, creds, { ...request, metric: "mrr" })).rejects.toThrow(
      /does not provide/,
    );
  });

  it("posts to the pinned Admin API version on the store's own domain", async () => {
    const ctx = stubContext({ NotchCustomersTotal: { data: { customersCount: null } } });
    await shopify.fetchMetric(ctx, creds, { ...request, metric: "customers" });
    expect(scalar(ctx.calls[0], "the call")).toBe(
      "https://acme-supply.myshopify.com/admin/api/2026-10/graphql.json",
    );
  });
});
