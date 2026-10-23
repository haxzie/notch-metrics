import { describe, expect, it } from "vitest";
import { stripe } from "../src/providers/stripe/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext, sub, expectMetrics } from "./helpers.ts";

const creds = { secret_key: "rk_test_abc123" };
const request = {
  metric: "mrr" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: {},
};

describe("stripe MRR", () => {
  it("normalises an annual plan to a twelfth of its price", async () => {
    const ctx = stubContext({
      "/subscriptions": {
        data: [sub({ id: "s1", amount: 120_000, interval: "year" })],
        has_more: false,
      },
    });
    const series = await stripe.fetchMetric(ctx, creds, request);
    // $1,200/year is $100/month: 120000 minor units ÷ 12 = 10000.
    expect(series.value).toBe(10_000);
    expect(series.currency).toBe("USD");
  });

  it("applies a percentage coupon", async () => {
    const ctx = stubContext({
      "/subscriptions": {
        data: [sub({ id: "s1", amount: 10_000, percentOff: 20 })],
        has_more: false,
      },
    });
    expect((await stripe.fetchMetric(ctx, creds, request)).value).toBe(8_000);
  });

  it("multiplies by quantity", async () => {
    const ctx = stubContext({
      "/subscriptions": { data: [sub({ id: "s1", amount: 2_500, quantity: 4 })], has_more: false },
    });
    expect((await stripe.fetchMetric(ctx, creds, request)).value).toBe(10_000);
  });

  it("excludes other currencies and says so, rather than adding them at 1:1", async () => {
    const ctx = stubContext({
      "/subscriptions": {
        data: [
          sub({ id: "s1", amount: 10_000, currency: "usd" }),
          sub({ id: "s2", amount: 90_000, currency: "jpy" }),
        ],
        has_more: false,
      },
    });
    const series = await stripe.fetchMetric(ctx, creds, request);
    expect(series.value).toBe(10_000);
    expect(series.note).toMatch(/another currency/);
  });

  it("refuses an account too large to total live instead of timing out", async () => {
    // Every page reports has_more, which is what a very large account looks
    // like. Without the page cap this walks until the Worker is killed.
    const page = { data: [sub({ id: "s1", amount: 100 })], has_more: true };
    const ctx = stubContext({ "/subscriptions": page });
    await expect(stripe.fetchMetric(ctx, creds, request)).rejects.toThrow(ProviderError);
    await expect(stripe.fetchMetric(ctx, creds, request)).rejects.toThrow(
      /too many|more .* than we can total/i,
    );
  });
});

describe("stripe revenue", () => {
  it("buckets charges by day and fills the empty days", async () => {
    const ctx = stubContext({
      "/balance_transactions": {
        data: [
          { id: "t1", amount: 1_000, currency: "usd", created: 1_790_812_800, type: "charge" },
          { id: "t2", amount: 2_500, currency: "usd", created: 1_790_812_801, type: "charge" },
        ],
        has_more: false,
      },
    });
    const series = await stripe.fetchMetric(ctx, creds, { ...request, metric: "revenue" });
    expect(series.value).toBe(3_500);
    // 5 Sept to 5 Oct inclusive is 31 daily buckets, gaps included — a
    // sparkline drawn from only the non-zero days misrepresents a quiet week.
    expect(series.points).toHaveLength(31);
    expect(scalar(series.points.find((p) => p.v > 0)).v).toBe(3_500);
  });

  it("omits the series when the widget only wants a number", async () => {
    const ctx = stubContext({ "/balance_transactions": { data: [], has_more: false } });
    const series = await stripe.fetchMetric(ctx, creds, {
      ...request,
      metric: "revenue",
      wantSeries: false,
    });
    expect(series.points).toEqual([]);
  });
});

describe("stripe verify", () => {
  it("narrows to revenue when the key cannot read subscriptions", async () => {
    const ctx = stubContext({
      "/account": { id: "acct_1", default_currency: "usd", business_profile: { name: "Acme" } },
      "/subscriptions": { __status: 403 },
    });
    const result = await stripe.verify(ctx, creds);
    expect(result.accountLabel).toBe("Acme");
    expect(result.currency).toBe("USD");
    expectMetrics(result.availableMetrics, ["revenue", "refunds", "recent_payments"]);
  });

  it("offers everything when the key is unrestricted", async () => {
    const ctx = stubContext({
      "/account": { id: "acct_1", default_currency: "eur", business_profile: null },
      "/subscriptions": { data: [], has_more: false },
    });
    const result = await stripe.verify(ctx, creds);
    expect(result.accountLabel).toBe("acct_1");
    expect(result.availableMetrics).toContain("mrr");
  });

  it("surfaces a 429 as rate_limited with the provider's own Retry-After", async () => {
    const ctx = stubContext({
      "/account": { __status: 429, __headers: { "retry-after": "30" } },
    });
    await expect(stripe.verify(ctx, creds)).rejects.toMatchObject({
      code: "rate_limited",
      retryAfterSeconds: 30,
    });
  });
});

describe("credentials", () => {
  it("rejects something that is not a Stripe key", () => {
    expect(stripe.credentialSchema.safeParse({ secret_key: "hunter2" }).success).toBe(false);
    expect(stripe.credentialSchema.safeParse({ secret_key: "rk_live_abc" }).success).toBe(true);
  });
});

describe("stripe recent payments", () => {
  it("lists succeeded charges with the payer's name and marks refunds", async () => {
    const ctx = stubContext({
      "/charges": {
        data: [
          {
            id: "ch_1",
            amount: 4_900,
            currency: "usd",
            created: 1_759_600_000,
            status: "succeeded",
            description: "Pro plan",
            billing_details: { name: "Ada Lovelace", email: "ada@example.com" },
          },
          { id: "ch_2", amount: 100, currency: "usd", created: 1_759_500_000, status: "failed" },
          {
            id: "ch_3",
            amount: 2_000,
            currency: "usd",
            created: 1_759_400_000,
            status: "succeeded",
            refunded: true,
            amount_refunded: 2_000,
            receipt_email: "grace@example.com",
            billing_details: { name: null, email: null },
          },
        ],
        has_more: false,
      },
    });
    const series = await stripe.fetchMetric(ctx, creds, { ...request, metric: "recent_payments" });
    const items = series.items ?? [];
    expect(items.map((i) => i.id)).toEqual(["ch_1", "ch_3"]);
    expect(scalar(items[0]).label).toBe("Ada Lovelace");
    expect(scalar(items[0]).detail).toBe("Pro plan");
    expect(scalar(items[0]).currency).toBe("USD");
    expect(scalar(items[1]).label).toBe("grace@example.com");
    expect(scalar(items[1]).status).toBe("refunded");
    expect(series.value).toBe(6_900);
  });
});
