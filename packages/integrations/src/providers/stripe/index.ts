import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { RECENT_PAYMENTS_LIMIT, recentPayments } from "../../list.ts";
import { bucketSum, toMonthly } from "../../normalise.ts";
import type {
  AdapterContext,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
  EventPage,
  RawEvent,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

const BASE = "https://api.stripe.com/v1";

export const credentialSchema = z.object({
  secret_key: z
    .string()
    .regex(/^(sk|rk)_(live|test)_[A-Za-z0-9]+$/, "That does not look like a Stripe secret key."),
});
export type StripeCredentials = z.infer<typeof credentialSchema>;

/**
 * An account with tens of thousands of subscriptions cannot have its MRR
 * computed by walking the list API inside a Worker's CPU budget. The cap turns
 * "the Worker died at 30s with no explanation" into an error that says what is
 * wrong and what the answer is (Stripe Sigma).
 */
const MAX_PAGES = 20;
const PAGE_SIZE = 100;

interface StripeList<T> {
  data: T[];
  has_more: boolean;
}

async function get<T>(
  ctx: AdapterContext,
  creds: StripeCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  const url = new URL(`${BASE}${path}`);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined) url.searchParams.set(k, String(v));
  }
  const response = await ctx.http(url.toString(), {
    headers: {
      authorization: `Bearer ${creds.secret_key}`,
      // Pinned, so Stripe changing a default shape cannot change our numbers
      // underneath us on a day we did not deploy.
      "stripe-version": "2024-06-20",
    },
  });
  if (!response.ok) throw errorForStatus("api.stripe.com", response);
  return response.json<T>();
}

async function walk<T extends { id: string }>(
  ctx: AdapterContext,
  creds: StripeCredentials,
  path: string,
  params: Record<string, string | number | undefined>,
): Promise<{ items: T[]; truncated: boolean }> {
  const items: T[] = [];
  let startingAfter: string | undefined;

  for (let page = 0; page < MAX_PAGES; page++) {
    const body = await get<StripeList<T>>(ctx, creds, path, {
      ...params,
      limit: PAGE_SIZE,
      starting_after: startingAfter,
    });
    items.push(...body.data);
    if (!body.has_more) return { items, truncated: false };
    // `at(-1)` rather than `[length - 1]`: with noUncheckedIndexedAccess the
    // latter is `T | undefined` anyway, and has_more with an empty page would
    // otherwise loop forever on the same cursor.
    const last = body.data.at(-1);
    if (!last) return { items, truncated: false };
    startingAfter = last.id;
  }

  return { items, truncated: true };
}

interface Subscription {
  id: string;
  status: string;
  created: number;
  canceled_at: number | null;
  currency: string;
  discounts?: { coupon?: { percent_off?: number | null } | null }[];
  items: {
    data: {
      quantity: number | null;
      price: {
        unit_amount: number | null;
        currency: string;
        recurring: { interval: string; interval_count: number } | null;
      } | null;
    }[];
  };
}

interface Charge {
  id: string;
  amount: number;
  amount_refunded?: number;
  currency: string;
  created: number;
  status: string;
  refunded?: boolean;
  description?: string | null;
  receipt_email?: string | null;
  billing_details?: { name?: string | null; email?: string | null } | null;
  failure_message?: string | null;
}

interface BalanceTransaction {
  id: string;
  amount: number;
  currency: string;
  created: number;
  type: string;
}

export const stripe: ProviderAdapter<StripeCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    const account = await get<{
      id: string;
      default_currency?: string;
      business_profile?: { name?: string | null } | null;
    }>(ctx, creds, "/account");

    // A restricted key may read charges but not subscriptions. Narrowing what
    // we offer beats failing the whole connection and telling the user their
    // perfectly good key is broken.
    const available: MetricId[] = ["revenue", "refunds", "recent_payments"];
    try {
      await get<StripeList<Subscription>>(ctx, creds, "/subscriptions", { limit: 1 });
      available.push("mrr", "active_subscribers", "new_subscribers", "churned_subscribers");
    } catch (error) {
      if (!(error instanceof ProviderError) || error.code !== "auth_failed") throw error;
      ctx.log("stripe key cannot read subscriptions; offering revenue only");
    }

    return {
      accountLabel: account.business_profile?.name ?? account.id,
      currency: account.default_currency?.toUpperCase() ?? null,
      availableMetrics: available,
    };
  },

  /**
   * Failed and refunded charges — the two things people actually want told,
   * and neither is a metric.
   *
   * One stream for both: `/charges` carries every outcome, so polling it once
   * serves both notification types rather than once each.
   */
  async fetchEvents(ctx, creds, request): Promise<EventPage> {
    if (request.stream !== "charges") return { events: [], cursor: null };

    const body = await get<StripeList<Charge>>(ctx, creds, "/charges", {
      limit: Math.min(request.limit, 100),
      // Stripe's own window, so the page is not walked back further than the
      // caller will accept anyway.
      "created[gte]": Math.floor(request.since.getTime() / 1000),
    });

    const events: RawEvent[] = [];
    for (const charge of body.data) {
      const at = new Date(charge.created * 1000);
      const who =
        charge.billing_details?.name ||
        charge.billing_details?.email ||
        charge.receipt_email ||
        "Customer";

      if (charge.status === "failed") {
        events.push({
          id: charge.id,
          type: "payment_failed",
          t: at,
          title: "Payment failed",
          // The provider's own reason, which is the whole value of being told.
          body: [who, charge.failure_message].filter(Boolean).join(" · ") || null,
          amount: charge.amount,
          currency: charge.currency.toUpperCase(),
          url: `https://dashboard.stripe.com/payments/${charge.id}`,
        });
      } else if (charge.refunded || (charge.amount_refunded ?? 0) > 0) {
        events.push({
          id: `${charge.id}:refund`,
          type: "refund_issued",
          t: at,
          title: "Refund issued",
          body: who,
          // The amount refunded, not the amount charged — a partial refund
          // reported as the full charge overstates it.
          amount: charge.amount_refunded ?? charge.amount,
          currency: charge.currency.toUpperCase(),
          url: `https://dashboard.stripe.com/payments/${charge.id}`,
        });
      }
    }

    // Stripe paginates by object id, and `has_more` tells us whether walking
    // on is worth it. The caller polls again rather than walking here, so a
    // busy account cannot turn one tick into an unbounded page walk.
    return {
      events,
      cursor: body.has_more ? (body.data[body.data.length - 1]?.id ?? null) : null,
    };
  },

  async fetchMetric(ctx, creds, request): Promise<RawSeries> {
    switch (request.metric) {
      case "mrr":
        return mrr(ctx, creds, request);
      case "active_subscribers":
        return activeSubscribers(ctx, creds, request);
      case "revenue":
        return balanceSeries(ctx, creds, request, "charge", 1);
      case "refunds":
        return balanceSeries(ctx, creds, request, "refund", -1);
      case "new_subscribers":
        return subscriptionCounts(ctx, creds, request, "created");
      case "churned_subscribers":
        return subscriptionCounts(ctx, creds, request, "canceled");
      case "recent_payments":
        return latestCharges(ctx, creds);
      default:
        // Exhaustive by construction: registry.test.ts asserts every metric the
        // manifest declares reaches a case above.
        throw new ProviderError("unsupported", `Stripe cannot produce ${request.metric}`);
    }
  },
};

/**
 * The newest charges that actually took money.
 *
 * Charges rather than balance transactions: a balance transaction knows the
 * amount and nothing about who paid. Over-fetched by a page so that a run
 * of failed card attempts does not leave the list short.
 */
async function latestCharges(ctx: AdapterContext, creds: StripeCredentials): Promise<RawSeries> {
  const body = await get<StripeList<Charge>>(ctx, creds, "/charges", {
    limit: RECENT_PAYMENTS_LIMIT * 2,
  });
  const rows = body.data
    .filter((charge) => charge.status === "succeeded")
    .map((charge) => ({
      id: charge.id,
      t: new Date(charge.created * 1000),
      label:
        charge.billing_details?.name ||
        charge.billing_details?.email ||
        charge.receipt_email ||
        "Customer",
      detail: charge.description ?? null,
      amount: charge.amount,
      currency: charge.currency.toUpperCase(),
      status: charge.refunded
        ? "refunded"
        : (charge.amount_refunded ?? 0) > 0
          ? "partially refunded"
          : charge.status,
    }));
  return recentPayments(ctx, rows);
}

function tooLarge(): ProviderError {
  return new ProviderError(
    "unsupported",
    "This account has more subscriptions than we can total live. Stripe Sigma support is coming.",
  );
}

/** Minor units of monthly recurring revenue, in the user's preferred currency. */
async function mrr(
  ctx: AdapterContext,
  creds: StripeCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const { items, truncated } = await walk<Subscription>(ctx, creds, "/subscriptions", {
    status: "active",
    "expand[]": "data.items.data.price",
  });
  if (truncated) throw tooLarge();

  const wanted = ctx.preferredCurrency.toLowerCase();
  let total = 0;
  let excluded = 0;

  for (const sub of items) {
    const discount = sub.discounts?.[0]?.coupon?.percent_off ?? 0;
    for (const item of sub.items.data) {
      const price = item.price;
      if (!price?.recurring || price.unit_amount === null) continue;
      if (price.currency.toLowerCase() !== wanted) {
        excluded++;
        continue;
      }
      const gross = price.unit_amount * (item.quantity ?? 1);
      const monthly = toMonthly(gross, price.recurring.interval, price.recurring.interval_count);
      total += monthly * (1 - discount / 100);
    }
  }

  const value = Math.round(total);
  return {
    unit: "currency",
    currency: ctx.preferredCurrency,
    // A snapshot. One point at `to` so a chart has something to draw, but
    // `supportsSeries` is false on this metric and the app renders a number.
    points: [{ t: request.to, v: value }],
    value,
    previousValue: null,
    note:
      excluded > 0
        ? `${excluded} subscription item${excluded === 1 ? "" : "s"} in another currency were excluded.`
        : undefined,
  };
}

async function activeSubscribers(
  ctx: AdapterContext,
  creds: StripeCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const { items, truncated } = await walk<Subscription>(ctx, creds, "/subscriptions", {
    status: "active",
  });
  if (truncated) throw tooLarge();
  return {
    unit: "count",
    currency: null,
    points: [{ t: request.to, v: items.length }],
    value: items.length,
    previousValue: null,
  };
}

async function balanceSeries(
  ctx: AdapterContext,
  creds: StripeCredentials,
  request: MetricRequest,
  type: "charge" | "refund",
  sign: 1 | -1,
): Promise<RawSeries> {
  const { items, truncated } = await walk<BalanceTransaction>(ctx, creds, "/balance_transactions", {
    type,
    "created[gte]": Math.floor(request.from.getTime() / 1000),
    "created[lte]": Math.floor(request.to.getTime() / 1000),
  });
  if (truncated) throw tooLarge();

  const wanted = ctx.preferredCurrency.toLowerCase();
  const kept = items.filter((t) => t.currency.toLowerCase() === wanted);
  const excluded = items.length - kept.length;

  const points = bucketSum(
    kept.map((t) => ({ at: new Date(t.created * 1000), amount: t.amount * sign })),
    {
      from: request.from,
      to: request.to,
      granularity: request.granularity,
      timeZone: ctx.timeZone,
    },
  );

  const value = points.reduce((sum, p) => sum + p.v, 0);
  return {
    unit: "currency",
    currency: ctx.preferredCurrency,
    points: request.wantSeries ? points : [],
    value,
    previousValue: null,
    note:
      excluded > 0
        ? `${excluded} transaction${excluded === 1 ? "" : "s"} in another currency were excluded.`
        : undefined,
  };
}

async function subscriptionCounts(
  ctx: AdapterContext,
  creds: StripeCredentials,
  request: MetricRequest,
  field: "created" | "canceled",
): Promise<RawSeries> {
  const from = Math.floor(request.from.getTime() / 1000);
  const to = Math.floor(request.to.getTime() / 1000);

  // Stripe can filter subscriptions by `created` but not by `canceled_at`, so
  // churn pulls cancelled subscriptions and buckets them client-side.
  const params: Record<string, string | number> =
    field === "created"
      ? { status: "all", "created[gte]": from, "created[lte]": to }
      : { status: "canceled" };

  const { items, truncated } = await walk<Subscription>(ctx, creds, "/subscriptions", params);
  if (truncated) throw tooLarge();

  const events = items
    .map((s) => (field === "created" ? s.created : s.canceled_at))
    .filter((at): at is number => at !== null && at >= from && at <= to)
    .map((at) => ({ at: new Date(at * 1000), amount: 1 }));

  const points = bucketSum(events, {
    from: request.from,
    to: request.to,
    granularity: request.granularity,
    timeZone: ctx.timeZone,
  });

  return {
    unit: "count",
    currency: null,
    points: request.wantSeries ? points : [],
    value: events.length,
    previousValue: null,
  };
}
