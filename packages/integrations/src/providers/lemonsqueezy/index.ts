import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { RECENT_PAYMENTS_LIMIT, recentPaymentsMetric } from "../../list.ts";
import { metricsFor, provider, type ScalarResult, type SeriesResult } from "../../metric.ts";
import { bucketSum, toMonthly } from "../../normalise.ts";
import type {
  AdapterContext,
  RawListItem,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

const BASE = "https://api.lemonsqueezy.com/v1";
const HOST = "api.lemonsqueezy.com";

const MAX_PAGES = 20;
const PAGE_SIZE = 100;

export const credentialSchema = z.object({
  api_key: z.string().min(20),
  store_id: z
    .string()
    .regex(/^\d+$/, "A Lemon Squeezy store ID is a number.")
    .optional()
    // An empty text field arrives as "", which is not a valid id and is not
    // the same as "not provided". Normalise before anything branches on it.
    .or(z.literal("").transform(() => undefined)),
});
export type LemonSqueezyCredentials = z.infer<typeof credentialSchema>;

/** JSON:API: every object is `{ id, attributes }`. */
interface Resource<A> {
  id: string;
  attributes: A;
}

interface Page<A> {
  data: Resource<A>[];
  meta?: { page?: { lastPage?: number; currentPage?: number } };
}

interface OrderAttributes {
  store_id: number;
  currency: string;
  total: number;
  status: string;
  refunded: boolean;
  refunded_amount: number;
  created_at: string;
  user_name?: string | null;
  user_email?: string | null;
  first_order_item?: { product_name?: string | null; variant_name?: string | null } | null;
}

interface SubscriptionAttributes {
  store_id: number;
  status: string;
  created_at: string;
  first_subscription_item?: { price_id: number; quantity: number } | null;
}

interface PriceAttributes {
  unit_price: number;
  category: string;
  renewal_interval_unit: string | null;
  renewal_interval_quantity: number | null;
}

async function get<T>(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  const url = new URL(`${BASE}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  const response = await ctx.http(url.toString(), {
    headers: {
      authorization: `Bearer ${creds.api_key}`,
      // Both are required. Lemon Squeezy answers 406 without the Accept
      // header, which looks like a routing problem rather than a missing
      // header.
      accept: "application/vnd.api+json",
      "content-type": "application/vnd.api+json",
    },
  });
  if (!response.ok) throw errorForStatus(HOST, response);
  return response.json<T>();
}

/**
 * Walks `page[number]` until a short page or `lastPage`.
 *
 * `stopWhen` lets a caller end the walk early on an ordering it knows about —
 * orders come back newest first, so a date-windowed query does not have to
 * read the whole history of the store.
 */
async function walk<A>(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
  path: string,
  params: Record<string, string | number | undefined>,
  stopWhen?: (row: Resource<A>) => boolean,
): Promise<{ items: Resource<A>[]; truncated: boolean }> {
  const items: Resource<A>[] = [];

  for (let page = 1; page <= MAX_PAGES; page++) {
    const body = await get<Page<A>>(ctx, creds, path, {
      ...params,
      "page[number]": page,
      "page[size]": PAGE_SIZE,
    });
    const batch = body.data ?? [];

    for (const row of batch) {
      if (stopWhen?.(row)) return { items, truncated: false };
      items.push(row);
    }

    const lastPage = body.meta?.page?.lastPage;
    if (batch.length < PAGE_SIZE) return { items, truncated: false };
    if (lastPage !== undefined && page >= lastPage) return { items, truncated: false };
  }

  return { items, truncated: true };
}

/**
 * Only the currencies the user asked for.
 *
 * Summing mixed currencies at 1:1 is the kind of wrong that looks right, so
 * other currencies are dropped and the exclusion is named in the note.
 */
function splitByCurrency(
  rows: Resource<OrderAttributes>[],
  preferred: string,
): { kept: Resource<OrderAttributes>[]; note?: string } {
  const want = preferred.toUpperCase();
  const kept = rows.filter((row) => row.attributes.currency.toUpperCase() === want);
  const others = new Set(
    rows.map((row) => row.attributes.currency.toUpperCase()).filter((code) => code !== want),
  );
  if (others.size === 0) return { kept };
  return {
    kept,
    note: `${[...others].sort().join(" and ")} excluded; totals are ${want} only.`,
  };
}

function truncationNote(truncated: boolean): string | undefined {
  return truncated
    ? `Only the first ${MAX_PAGES * PAGE_SIZE} records were read, so this is an undercount.`
    : undefined;
}

function join(...notes: (string | undefined)[]): string | undefined {
  const present = notes.filter((note): note is string => Boolean(note));
  return present.length ? present.join(" ") : undefined;
}

function storeFilter(creds: LemonSqueezyCredentials): Record<string, string | undefined> {
  return creds.store_id ? { "filter[store_id]": creds.store_id } : {};
}

async function activeSubscriptions(ctx: AdapterContext, creds: LemonSqueezyCredentials) {
  return walk<SubscriptionAttributes>(ctx, creds, "/subscriptions", {
    ...storeFilter(creds),
    "filter[status]": "active",
  });
}

/**
 * A snapshot of the subscription book, not a total over a window.
 *
 * A Lemon Squeezy subscription carries no amount — only a `price_id` — so the
 * prices have to be fetched separately. They are deduplicated first: a store
 * with 800 subscribers typically has a handful of prices, and one request per
 * subscription would exhaust the Worker's budget on a mid-sized store.
 */
async function mrrValue(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
): Promise<ScalarResult> {
  const { items, truncated } = await activeSubscriptions(ctx, creds);

  const priceIds = [
    ...new Set(
      items
        .map((row) => row.attributes.first_subscription_item?.price_id)
        .filter((id): id is number => typeof id === "number"),
    ),
  ];

  const prices = new Map<number, PriceAttributes>();
  for (const id of priceIds) {
    const body = await get<{ data: Resource<PriceAttributes> }>(ctx, creds, `/prices/${id}`);
    if (body.data) prices.set(id, body.data.attributes);
  }

  let total = 0;
  let unpriced = 0;

  for (const row of items) {
    const item = row.attributes.first_subscription_item;
    const price = item ? prices.get(item.price_id) : undefined;
    if (!price || price.category !== "subscription" || !price.renewal_interval_unit) {
      unpriced += 1;
      continue;
    }
    total += toMonthly(
      price.unit_price * (item?.quantity ?? 1),
      price.renewal_interval_unit,
      price.renewal_interval_quantity ?? 1,
    );
  }

  // Minor units are integers. Rounding once at the end rather than per
  // subscription keeps an annual plan's twelfth from drifting across a book.
  const value = Math.round(total);

  return {
    // The store's currency, which `verify` recorded. Lemon Squeezy prices
    // carry no currency of their own — a store has exactly one.
    currency: ctx.preferredCurrency,
    value,
    note: join(
      unpriced > 0
        ? `${unpriced} subscription${unpriced === 1 ? "" : "s"} had no recurring price and were excluded.`
        : undefined,
      truncationNote(truncated),
    ),
  };
}

async function activeCount(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
): Promise<ScalarResult> {
  const { items, truncated } = await activeSubscriptions(ctx, creds);
  return { value: items.length, note: truncationNote(truncated) };
}

/** Orders took payment. `pending`, `failed` and `fraudulent` did not. */
const PAID = new Set(["paid", "refunded", "partial_refund"]);

async function fromOrders(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
  request: MetricRequest,
  /**
   * Which amount on an order this metric is.
   *
   * Passed in rather than read off `request.metric`: revenue and refunds are
   * the same walk over the same orders, and the only difference between them
   * is this line.
   */
  amountOf: (row: Resource<OrderAttributes>) => number,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  // Lemon Squeezy cannot filter orders by date, but it returns them newest
  // first — so the walk stops at the first order older than the window
  // instead of reading the store's whole history.
  const { items, truncated } = await walk<OrderAttributes>(
    ctx,
    creds,
    "/orders",
    storeFilter(creds),
    (row) => new Date(row.attributes.created_at) < from,
  );

  const paid = items.filter(
    (row) => PAID.has(row.attributes.status) && new Date(row.attributes.created_at) <= request.to,
  );
  const { kept, note } = splitByCurrency(paid, ctx.preferredCurrency);

  const events = kept
    .map((row) => ({ at: new Date(row.attributes.created_at), amount: amountOf(row) }))
    .filter((event) => event.amount > 0);

  const points = bucketSum(events, {
    from: request.from,
    to: request.to,
    granularity: request.granularity,
    timeZone: ctx.timeZone,
  });

  const inWindow = (at: Date) => at >= request.from && at <= request.to;
  const value = events.filter((e) => inWindow(e.at)).reduce((sum, e) => sum + e.amount, 0);
  const previousValue = request.comparePrevious
    ? events.filter((e) => !inWindow(e.at)).reduce((sum, e) => sum + e.amount, 0)
    : null;

  return {
    currency: ctx.preferredCurrency,
    points,
    value,
    previousValue,
    note: join(note, truncationNote(truncated)),
  };
}

/** The newest paid orders. Orders come back newest first, so one page does. */
async function latestOrders(
  ctx: AdapterContext,
  creds: LemonSqueezyCredentials,
): Promise<RawListItem[]> {
  const body = await get<Page<OrderAttributes>>(ctx, creds, "/orders", {
    ...storeFilter(creds),
    "page[number]": 1,
    "page[size]": RECENT_PAYMENTS_LIMIT * 2,
  });
  const rows = (body.data ?? [])
    .filter((row) => PAID.has(row.attributes.status))
    .map((row) => {
      const item = row.attributes.first_order_item;
      const product = [item?.product_name, item?.variant_name]
        .filter((part): part is string => Boolean(part))
        .join(" · ");
      return {
        id: row.id,
        t: new Date(row.attributes.created_at),
        label: row.attributes.user_name || row.attributes.user_email || "Customer",
        detail: product || null,
        amount: row.attributes.total,
        currency: row.attributes.currency.toUpperCase(),
        status: row.attributes.status,
      };
    });
  // Sorted, capped and totalled by the shared payments metric.
  return rows;
}

const { scalar, series } = metricsFor<LemonSqueezyCredentials>();

export const mrr = scalar({
  id: "mrr",
  label: "Monthly recurring revenue",
  shortLabel: "MRR",
  unit: "currency",
  freshnessSeconds: 180,
  methodology:
    "Active subscriptions, each price normalised to a monthly amount by its renewal interval. A snapshot of the book right now, not a total over the window.",
  fetch: mrrValue,
});

export const revenue = series({
  id: "revenue",
  label: "Revenue",
  shortLabel: "Revenue",
  unit: "currency",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Orders in the window that took payment, by `total`. Gross: a later refund does not remove the order from the day it was paid.",
  fetch: (ctx, creds, request) => fromOrders(ctx, creds, request, (row) => row.attributes.total),
});

export const activeSubscribers = scalar({
  id: "active_subscribers",
  label: "Active subscribers",
  shortLabel: "Active",
  unit: "count",
  freshnessSeconds: 180,
  methodology: "Subscriptions in status `active` right now, trials included.",
  fetch: activeCount,
});

export const refunds = series({
  id: "refunds",
  label: "Refunds",
  shortLabel: "Refunds",
  unit: "currency",
  compare: true,
  granularities: ["day", "week", "month"],
  // Bucketed by the order's own date, because Lemon Squeezy does not
  // expose when the refund happened — only that it did and for how much.
  freshnessSeconds: 60,
  methodology:
    "`refunded_amount` on orders in the window, bucketed by the order date rather than the refund date, which the API does not expose.",
  fetch: (ctx, creds, request) =>
    fromOrders(ctx, creds, request, (row) => row.attributes.refunded_amount),
});

export const payments = recentPaymentsMetric<LemonSqueezyCredentials>({
  methodology:
    "The latest orders that took payment, newest first, with the buyer's name or email and the first product on the order. The headline is their total in your currency.",
  rows: latestOrders,
});

export const lemonsqueezy = provider({
  metrics: [mrr, revenue, activeSubscribers, refunds, payments],
  manifest,
  credentialSchema,

  async verify(ctx, creds) {
    const me = await get<{ data: Resource<{ name?: string; email?: string }> }>(
      ctx,
      creds,
      "/users/me",
    );

    const stores = await get<{ data: Resource<{ name?: string; currency?: string }>[] }>(
      ctx,
      creds,
      "/stores",
      { "page[size]": 100 },
    );

    const chosen = creds.store_id
      ? stores.data?.find((store) => store.id === creds.store_id)
      : stores.data?.[0];

    // A store id that does not belong to this key would otherwise fail later
    // as an empty dashboard rather than a rejected connection.
    if (creds.store_id && !chosen) {
      throw new ProviderError("unsupported", `This API key cannot see store ${creds.store_id}.`);
    }

    const label = creds.store_id
      ? (chosen?.attributes.name ?? `Store ${creds.store_id}`)
      : (me.data?.attributes.name ?? me.data?.attributes.email ?? "Lemon Squeezy");

    // No `availableMetrics`: it was these five ids written out a second time
    // beside the manifest and the switch. Derived from the metrics now.
    return {
      accountLabel: label,
      currency: chosen?.attributes.currency?.toUpperCase() ?? null,
    };
  },
});
