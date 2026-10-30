import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForResponse } from "../../http.ts";
import { RECENT_PAYMENTS_LIMIT, recentPaymentsMetric } from "../../list.ts";
import { metricsFor, provider, type ScalarResult, type SeriesResult } from "../../metric.ts";
import { bucketSum, toMinorUnits } from "../../normalise.ts";
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

/**
 * Pinned, never `latest` or `unstable`.
 *
 * A Shopify version is supported for twelve months and then starts answering
 * with the next one's shapes. Pinning means an upgrade is a commit with a test
 * run behind it; `latest` means the store's numbers change on Shopify's
 * release day, in production, on a Tuesday.
 */
const API_VERSION = "2026-10";

/**
 * Orders are read by walking the `orders` connection rather than by asking
 * ShopifyQL (`shopifyqlQuery`) for a pre-aggregated series.
 *
 * ShopifyQL would be cheaper and would match the merchant's own Analytics
 * page exactly — but it needs `read_reports`, which is a separate scope from
 * the two a merchant grants to let us read their store, and it is not
 * available on every Shopify plan. A connector that works for everyone who
 * grants `read_orders` beats one that is exact for some and broken for the
 * rest.
 *
 * The cost of that choice is this cap. Shopify's GraphQL budget is points per
 * second, not requests, and a page of 120 orders with two money bags each
 * costs about 600 of a standard store's 1000 — so the walk is bounded and
 * says so in the series note rather than quietly reporting a fraction of a
 * busy month.
 */
const PAGE_SIZE = 120;
const MAX_PAGES = 5;

/** Customers carry no nested objects, so a page of them is cheap. */
const CUSTOMER_PAGE_SIZE = 250;
const CUSTOMER_MAX_PAGES = 4;

export const credentialSchema = z.object({
  shop_domain: z
    .string()
    .min(3)
    // Normalised before anything branches on it: people paste
    // `https://my-store.myshopify.com/admin`, and every one of those forms is
    // the same store. Idempotent, because this schema also parses the blob
    // back out of the database.
    .transform(normaliseShopDomain)
    .refine(
      (host) => /^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(host),
      "A Shopify store's Admin API lives on its .myshopify.com domain, not on a custom storefront domain.",
    ),
  access_token: z
    .string()
    .regex(/^shp(at|ca)_[A-Za-z0-9]+$/, "An Admin API access token starts with shpat_."),
});
export type ShopifyCredentials = z.infer<typeof credentialSchema>;

/**
 * `https://My-Store.myshopify.com/admin/` → `my-store.myshopify.com`.
 *
 * A bare handle gets the suffix. Anything else is left alone for the refine
 * above to reject by name — silently rewriting `shop.example.com` into
 * `shop.example.com.myshopify.com` would fail later as a 404 that reads like
 * a deleted store.
 */
export function normaliseShopDomain(input: string): string {
  const trimmed = input.trim().toLowerCase();
  const withoutScheme = trimmed.replace(/^https?:\/\//, "");
  const host = withoutScheme.split("/")[0] ?? "";
  if (host.length > 0 && !host.includes(".")) return `${host}.myshopify.com`;
  return host;
}

interface MoneyBag {
  shopMoney: { amount: string; currencyCode: string };
}

interface OrderNode {
  id: string;
  name: string;
  createdAt: string;
  test: boolean;
  displayFinancialStatus: string | null;
  totalPriceSet: MoneyBag | null;
  totalRefundedSet: MoneyBag | null;
  customer?: { displayName: string | null; email: string | null } | null;
  lineItems?: { nodes: { title: string | null }[] } | null;
}

interface PageInfo {
  hasNextPage: boolean;
  endCursor: string | null;
}

interface GraphQLError {
  message: string;
  extensions?: { code?: string };
}

interface GraphQLBody<T> {
  data?: T | null;
  errors?: GraphQLError[] | string;
  extensions?: {
    cost?: {
      requestedQueryCost?: number;
      throttleStatus?: { currentlyAvailable?: number; restoreRate?: number };
    };
  };
}

/** Raised mid-walk so a partial total can be reported with a note. */
class Throttled extends Error {
  readonly retryAfterSeconds: number;
  constructor(retryAfterSeconds: number) {
    super("throttled");
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

function endpoint(creds: ShopifyCredentials): string {
  return `https://${creds.shop_domain}/admin/api/${API_VERSION}/graphql.json`;
}

/**
 * One POST, one error taxonomy.
 *
 * Shopify answers a *200* for most of what went wrong: a missing scope, a
 * throttle and a query that costs too much all arrive as `errors` beside a
 * null `data`. Reading only the status code here would turn every one of them
 * into an empty tile with no explanation.
 */
async function graphql<T>(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
  query: string,
  variables: Record<string, unknown> = {},
  options: { tolerateErrors?: boolean } = {},
): Promise<T> {
  const response = await ctx.http(endpoint(creds), {
    method: "POST",
    headers: {
      "x-shopify-access-token": creds.access_token,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });

  if (!response.ok) {
    // 402 is a store whose Shopify bill is unpaid or whose plan excludes the
    // API; 423 is one Shopify has locked. Both read as "rejected the
    // credentials" through the generic mapping, which sends the user looking
    // for a key problem they do not have.
    if (response.status === 402) {
      throw new ProviderError(
        "unsupported",
        `${creds.shop_domain} is frozen or on a plan without Admin API access.`,
      );
    }
    if (response.status === 423) {
      throw new ProviderError("unsupported", `${creds.shop_domain} is locked.`);
    }
    if (response.status === 404) {
      throw new ProviderError(
        "auth_failed",
        `${creds.shop_domain} does not exist, or the app has been uninstalled from it.`,
      );
    }
    throw await errorForResponse(creds.shop_domain, response);
  }

  const body = await response.json<GraphQLBody<T>>();
  const errors = Array.isArray(body.errors) ? body.errors : [];

  if (typeof body.errors === "string") {
    throw new ProviderError("bad_response", `${creds.shop_domain}: ${body.errors}`);
  }

  for (const error of errors) {
    const code = error.extensions?.code;
    if (code === "THROTTLED") throw new Throttled(retryAfter(body));
    if (code === "MAX_COST_EXCEEDED") {
      throw new ProviderError("unsupported", "Shopify refused the query as too large to run.");
    }
    if (code === "ACCESS_DENIED" || /access denied/i.test(error.message)) {
      // The message names the scope — "Required access: `read_orders`" — and
      // that sentence is the whole fix, so it is passed through rather than
      // flattened into "rejected the credentials".
      if (!options.tolerateErrors) {
        throw new ProviderError("auth_failed", error.message);
      }
    }
  }

  if (body.data === null || body.data === undefined) {
    const first = errors[0]?.message ?? "no data";
    throw new ProviderError("bad_response", `${creds.shop_domain}: ${first}`);
  }

  if (errors.length > 0 && !options.tolerateErrors) {
    throw new ProviderError("bad_response", `${creds.shop_domain}: ${errors[0]?.message}`);
  }

  return body.data;
}

/**
 * How long Shopify's own bucket needs to refill enough for the query we just
 * tried. Honoured by the scheduler, so a throttled store backs off by the
 * right amount rather than by a guess.
 */
function retryAfter(body: GraphQLBody<unknown>): number {
  const cost = body.extensions?.cost;
  const needed = cost?.requestedQueryCost ?? 0;
  const available = cost?.throttleStatus?.currentlyAvailable ?? 0;
  const restoreRate = cost?.throttleStatus?.restoreRate ?? 50;
  const seconds = Math.ceil((needed - available) / Math.max(1, restoreRate));
  return Math.min(60, Math.max(1, Number.isFinite(seconds) ? seconds : 2));
}

/** A Shopify search-syntax window. Inclusive at both ends, like the request. */
function createdBetween(from: Date, to: Date): string {
  return `created_at:>='${from.toISOString()}' created_at:<='${to.toISOString()}'`;
}

const ORDERS_PAGE = `
  query NotchOrders($first: Int!, $after: String, $query: String!) {
    orders(first: $first, after: $after, query: $query, sortKey: CREATED_AT, reverse: true) {
      nodes {
        id
        name
        createdAt
        test
        displayFinancialStatus
        totalPriceSet { shopMoney { amount currencyCode } }
        totalRefundedSet { shopMoney { amount currencyCode } }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

const RECENT_ORDERS = `
  query NotchRecentOrders($first: Int!) {
    orders(first: $first, sortKey: CREATED_AT, reverse: true) {
      nodes {
        id
        name
        createdAt
        test
        displayFinancialStatus
        totalPriceSet { shopMoney { amount currencyCode } }
        totalRefundedSet { shopMoney { amount currencyCode } }
        customer { displayName email }
        lineItems(first: 1) { nodes { title } }
      }
    }
  }
`;

const CUSTOMERS_PAGE = `
  query NotchCustomers($first: Int!, $after: String, $query: String!) {
    customers(first: $first, after: $after, query: $query, sortKey: CREATED_AT, reverse: true) {
      nodes { id createdAt }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

const CUSTOMERS_TOTAL = `
  query NotchCustomersTotal {
    customersCount { count precision }
  }
`;

const VERIFY = `
  query NotchVerify {
    shop { name currencyCode myshopifyDomain }
    ordersCount(limit: 1) { count }
    customersCount(limit: 1) { count }
  }
`;

/**
 * An order that took money.
 *
 * `AUTHORIZED` and `PENDING` have not: an authorisation can expire and a
 * pending bank transfer can never arrive, and counting either as a sale makes
 * today's revenue drift downwards over the following week.
 */
const PAID = new Set(["PAID", "PARTIALLY_PAID", "PARTIALLY_REFUNDED", "REFUNDED"]);

interface Walked {
  orders: OrderNode[];
  /** Hit the page cap or a throttle: every total from this walk is a floor. */
  truncated: boolean;
  throttledAfter: number | null;
}

async function walkOrders(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
  from: Date,
  to: Date,
): Promise<Walked> {
  const orders: OrderNode[] = [];
  let after: string | null = null;

  for (let page = 0; page < MAX_PAGES; page++) {
    let body: { orders: { nodes: OrderNode[]; pageInfo: PageInfo } };
    try {
      body = await graphql(ctx, creds, ORDERS_PAGE, {
        first: PAGE_SIZE,
        after,
        query: createdBetween(from, to),
      });
    } catch (error) {
      if (error instanceof Throttled) {
        // The first page is an error — there is nothing to show. A later one
        // is a bounded undercount, which the note explains, and that beats
        // blanking a tile that already has most of the month in it.
        if (orders.length === 0) {
          throw new ProviderError(
            "rate_limited",
            `${creds.shop_domain} is rate limited`,
            error.retryAfterSeconds,
          );
        }
        return { orders, truncated: true, throttledAfter: orders.length };
      }
      throw error;
    }

    orders.push(...body.orders.nodes);
    if (!body.orders.pageInfo.hasNextPage) {
      return { orders, truncated: false, throttledAfter: null };
    }
    after = body.orders.pageInfo.endCursor;
    if (after === null) return { orders, truncated: false, throttledAfter: null };
  }

  return { orders, truncated: true, throttledAfter: null };
}

function paidOrders(walked: Walked): OrderNode[] {
  return walked.orders.filter(
    (order) => !order.test && PAID.has(order.displayFinancialStatus ?? ""),
  );
}

/**
 * Shopify reports money as a decimal string in the shop's currency.
 *
 * Reported in that currency rather than converted into the user's preferred
 * one, and rather than filtered down to it the way a multi-currency payment
 * processor's rows are: `shopMoney` is *already* one currency — the store's —
 * so there is nothing to exclude, and inventing a rate would be the kind of
 * wrong that looks right.
 */
function money(bag: MoneyBag | null): { amount: number; currency: string } | null {
  if (!bag?.shopMoney) return null;
  const currency = bag.shopMoney.currencyCode.toUpperCase();
  const parsed = Number(bag.shopMoney.amount);
  if (!Number.isFinite(parsed)) return null;
  return { amount: toMinorUnits(parsed, currency), currency };
}

function shopCurrency(orders: OrderNode[], fallback: string): string {
  for (const order of orders) {
    const total = money(order.totalPriceSet);
    if (total) return total.currency;
  }
  return fallback;
}

function notes(...parts: (string | undefined)[]): string | undefined {
  const present = parts.filter((part): part is string => Boolean(part));
  return present.length ? present.join(" ") : undefined;
}

function truncationNote(walked: Walked): string | undefined {
  if (!walked.truncated) return undefined;
  if (walked.throttledAfter !== null) {
    return `Shopify rate limited the request after ${walked.throttledAfter} orders, so this is an undercount.`;
  }
  return `Only the ${MAX_PAGES * PAGE_SIZE} most recent orders in the window were read, so this is an undercount.`;
}

/**
 * The store's currency against the user's preference.
 *
 * Said once, in the note, rather than hidden: a tile labelled in EUR next to
 * one labelled in USD is confusing only until somebody explains why.
 */
function currencyNote(currency: string, preferred: string): string | undefined {
  if (currency === preferred.toUpperCase()) return undefined;
  return `Totals are in the store's own currency, ${currency}, not ${preferred.toUpperCase()}.`;
}

/**
 * A `Throttled` nobody caught is still a rate limit, not a crash.
 *
 * Only the order walk has something useful to do with one — report the part
 * it already has. Everywhere else it has to become a `ProviderError` before
 * it leaves the adapter, or the Worker logs an unhandled `Error: throttled`
 * and the tile says "something went wrong".
 */
function rethrow(error: unknown): never {
  if (error instanceof Throttled) {
    throw new ProviderError(
      "rate_limited",
      "Shopify is rate limiting this store",
      error.retryAfterSeconds,
    );
  }
  throw error;
}

async function verifyToken(ctx: AdapterContext, creds: ShopifyCredentials) {
  // One round trip, tolerating per-field errors: a token missing
  // `read_customers` returns the shop and a null `customersCount` beside an
  // ACCESS_DENIED, and narrowing on that is better than rejecting a key that
  // reads orders perfectly well.
  const data = await graphql<{
    shop: { name: string | null; currencyCode: string | null } | null;
    ordersCount: { count: number } | null;
    customersCount: { count: number } | null;
  }>(ctx, creds, VERIFY, {}, { tolerateErrors: true });

  if (!data.shop) {
    throw new ProviderError(
      "auth_failed",
      `${creds.shop_domain} rejected the token, or the app it belongs to has no API access.`,
    );
  }

  const canReadOrders = data.ordersCount !== null;
  const canReadCustomers = data.customersCount !== null;

  if (!canReadOrders && !canReadCustomers) {
    throw new ProviderError(
      "auth_failed",
      "This token can read neither orders nor customers. Add the read_orders and read_customers scopes to the app, then reinstall it.",
    );
  }

  // Said as what the token *cannot* read. `provider()` derives the available
  // set from the metrics, so this is no longer a second list of them.
  const unavailableMetrics: MetricId[] = [
    ...(canReadOrders
      ? []
      : (["revenue", "orders", "average_order_value", "refunds", "recent_payments"] as const)),
    ...(canReadCustomers ? [] : (["customers", "new_customers"] as const)),
  ];

  return {
    accountLabel: data.shop.name ?? creds.shop_domain.replace(/\.myshopify\.com$/, ""),
    currency: data.shop.currencyCode?.toUpperCase() ?? null,
    unavailableMetrics,
  };
}

/**
 * Sales, orders, AOV and refunds, all from one walk.
 *
 * One walk rather than four because a user with those four tiles in the notch
 * sends them as one batch: four walks of the same window would be four times
 * the Shopify budget for exactly the same orders. They disagree about what to
 * *do* with an order, not about which orders there are.
 */
async function fromOrders(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
  request: MetricRequest,
  /**
   * What this metric wants out of the shared walk.
   *
   * `revenue` and `refunds` differ only in which money bag they read;
   * `orders` counts rows; `average_order_value` is the window's own ratio.
   * All four were `case` labels falling through to one body that then
   * switched on `request.metric` twice more.
   */
  kind: "money" | "count" | "average",
  /** Which bag a money metric reads. Ignored by the other two. */
  bag: (order: OrderNode) => number = (order) => money(order.totalPriceSet)?.amount ?? 0,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  const walked = await walkOrders(ctx, creds, from, request.to);
  const paid = paidOrders(walked);
  const currency = shopCurrency(paid, ctx.preferredCurrency);

  const events = paid.map((order) => ({
    at: new Date(order.createdAt),
    amount: bag(order),
  }));

  const inWindow = (at: Date) => at >= request.from && at <= request.to;
  const current = events.filter((event) => inWindow(event.at));
  const previous = events.filter((event) => !inWindow(event.at));
  const sum = (rows: { amount: number }[]) => rows.reduce((total, row) => total + row.amount, 0);

  const bucket = (rows: { at: Date; amount: number }[]) =>
    bucketSum(rows, {
      from: request.from,
      to: request.to,
      granularity: request.granularity,
      timeZone: ctx.timeZone,
    });

  if (kind === "count") {
    const counted = current.map((event) => ({ at: event.at, amount: 1 }));
    return {
      points: bucket(counted),
      value: current.length,
      previousValue: request.comparePrevious ? previous.length : null,
      note: truncationNote(walked),
    };
  }

  if (kind === "average") {
    // The headline is the window's own ratio, not the mean of the points: a
    // Tuesday with two orders would otherwise weigh as much as a Black Friday
    // with four hundred.
    const totals = bucket(current);
    const counts = bucket(current.map((event) => ({ at: event.at, amount: 1 })));
    return {
      currency,
      // Same from, to and granularity, so the two walks produce the same
      // bucket sequence and can be zipped by index.
      points: totals.map((point, index) => ({
        t: point.t,
        v: divide(point.v, counts[index]?.v ?? 0),
      })),
      value: divide(sum(current), current.length),
      previousValue: request.comparePrevious ? divide(sum(previous), previous.length) : null,
      note: notes(currencyNote(currency, ctx.preferredCurrency), truncationNote(walked)),
    };
  }

  return {
    currency,
    points: bucket(current),
    value: sum(current),
    previousValue: request.comparePrevious ? sum(previous) : null,
    note: notes(currencyNote(currency, ctx.preferredCurrency), truncationNote(walked)),
  };
}

/** Zero rather than NaN: a day with no orders has no average, and 0 renders. */
function divide(total: number, count: number): number {
  return count === 0 ? 0 : Math.round(total / count);
}

async function latestOrders(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
): Promise<RawListItem[]> {
  // Twice the limit, because the newest orders include the unpaid ones and
  // those are filtered out here rather than by Shopify.
  const data = await graphql<{ orders: { nodes: OrderNode[] } }>(ctx, creds, RECENT_ORDERS, {
    first: RECENT_PAYMENTS_LIMIT * 2,
  });

  const paid = data.orders.nodes.filter(
    (order) => !order.test && PAID.has(order.displayFinancialStatus ?? ""),
  );

  const rows = paid.map((order) => {
    const total = money(order.totalPriceSet);
    const product = order.lineItems?.nodes[0]?.title ?? null;
    return {
      id: order.id,
      t: new Date(order.createdAt),
      // The order number is the fallback rather than "Customer": every
      // Shopify order has one, it is what the merchant searches by, and a
      // list of ten rows all reading "Customer" identifies nothing.
      label: order.customer?.displayName || order.customer?.email || order.name,
      detail: product,
      amount: total?.amount ?? null,
      currency: total?.currency ?? null,
      status: order.displayFinancialStatus?.toLowerCase() ?? null,
    };
  });

  // `recentPayments` totals the rows that are in the context's preferred
  // currency, and a store's rows are all in the store's. Handing it the
  // store's currency is what keeps the headline from reading zero for a
  // merchant in Berlin whose account preference still says USD.
  return rows;
}

async function newCustomers(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  const rows: { createdAt: string }[] = [];
  let after: string | null = null;
  let truncated = true;

  for (let page = 0; page < CUSTOMER_MAX_PAGES; page++) {
    const data: { customers: { nodes: { createdAt: string }[]; pageInfo: PageInfo } } =
      await graphql(ctx, creds, CUSTOMERS_PAGE, {
        first: CUSTOMER_PAGE_SIZE,
        after,
        query: createdBetween(from, request.to),
      });
    rows.push(...data.customers.nodes);
    if (!data.customers.pageInfo.hasNextPage || data.customers.pageInfo.endCursor === null) {
      truncated = false;
      break;
    }
    after = data.customers.pageInfo.endCursor;
  }

  const events = rows.map((row) => ({ at: new Date(row.createdAt), amount: 1 }));
  const inWindow = (at: Date) => at >= request.from && at <= request.to;
  const current = events.filter((event) => inWindow(event.at));

  return {
    points: bucketSum(current, {
      from: request.from,
      to: request.to,
      granularity: request.granularity,
      timeZone: ctx.timeZone,
    }),
    value: current.length,
    previousValue: request.comparePrevious ? events.length - current.length : null,
    note: truncated
      ? `Only the first ${CUSTOMER_MAX_PAGES * CUSTOMER_PAGE_SIZE} customers in the window were read, so this is an undercount.`
      : undefined,
  };
}

async function totalCustomers(
  ctx: AdapterContext,
  creds: ShopifyCredentials,
): Promise<ScalarResult> {
  const data = await graphql<{ customersCount: { count: number; precision: string } | null }>(
    ctx,
    creds,
    CUSTOMERS_TOTAL,
  );
  const count = data.customersCount?.count ?? 0;

  return {
    value: count,
    // Shopify stops counting at ten thousand and says so in `precision`.
    // Passing that on matters: the tile is otherwise a store's growth
    // flatlining at exactly 10,000 with no explanation.
    note:
      data.customersCount?.precision === "AT_LEAST"
        ? "Shopify reports this as a floor rather than an exact count above ten thousand."
        : undefined,
  };
}

const { scalar, series } = metricsFor<ShopifyCredentials>();

/**
 * Shopify's throttling arrives as a `Throttled`, not a `ProviderError`, and
 * every call out of this file has to translate it.
 *
 * It used to sit on the adapter's two members. Per metric that would be six
 * chances to forget the `.catch`, so it is a wrapper instead.
 */
function guarded<A extends unknown[], R>(
  inner: (...args: A) => Promise<R>,
): (...args: A) => Promise<R> {
  return (...args) => inner(...args).catch(rethrow);
}

export const revenue = series({
  id: "revenue",
  label: "Sales",
  shortLabel: "Sales",
  unit: "currency",
  compare: true,
  granularities: ["hour", "day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Order totals for orders placed in the window that took payment, in the store's own currency. Gross: a later refund does not remove the order from the day it was placed. The Refunds widget is the other half.",
  fetch: guarded((ctx, creds, request) => fromOrders(ctx, creds, request, "money")),
});

export const orders = series({
  id: "orders",
  label: "Orders",
  shortLabel: "Orders",
  unit: "count",
  compare: true,
  granularities: ["hour", "day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Orders placed in the window that took payment. Test orders and abandoned or unpaid checkouts are excluded, so this sits below the Shopify admin's own order count when the store has pending orders.",
  fetch: guarded((ctx, creds, request) => fromOrders(ctx, creds, request, "count")),
});

export const averageOrderValue = series({
  id: "average_order_value",
  label: "Average order value",
  shortLabel: "AOV",
  unit: "currency",
  compare: true,
  granularities: ["hour", "day", "week", "month"],
  // The headline is the window's own ratio, not the mean of the daily
  // ones: averaging averages weights a Tuesday with two orders the same
  // as a Black Friday with four hundred.
  freshnessSeconds: 300,
  methodology:
    "Sales divided by orders over the whole window. Each point is that day's own ratio, so the headline is not the average of the points.",
  fetch: guarded((ctx, creds, request) => fromOrders(ctx, creds, request, "average")),
});

export const refunds = series({
  id: "refunds",
  label: "Refunds",
  shortLabel: "Refunds",
  unit: "currency",
  compare: true,
  granularities: ["hour", "day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Amounts refunded against orders placed in the window, bucketed by the order's date rather than the refund's. A refund of a much older order is not counted here.",
  fetch: guarded((ctx, creds, request) =>
    fromOrders(ctx, creds, request, "money", (order) => money(order.totalRefundedSet)?.amount ?? 0),
  ),
});

export const newCustomersMetric = series({
  id: "new_customers",
  label: "New customers",
  shortLabel: "New",
  unit: "count",
  compare: true,
  granularities: ["hour", "day", "week", "month"],
  freshnessSeconds: 300,
  methodology:
    "Customer records created in the window. Shopify creates one at checkout, so a guest who buys twice counts once. Somebody who only signed up for the newsletter counts too.",
  fetch: guarded(newCustomers),
});

export const customers = scalar({
  id: "customers",
  label: "Customers",
  shortLabel: "Customers",
  unit: "count",
  freshnessSeconds: 300,
  methodology:
    "Every customer record on the store right now, which is what the admin's Customers page counts. Shopify reports this as an estimate above ten thousand.",
  fetch: guarded(totalCustomers),
});

export const payments = recentPaymentsMetric<ShopifyCredentials>({
  methodology:
    "The latest orders that took payment, newest first, with the buyer's name and the first product on the order. The headline is their total in the store's currency.",
  rows: guarded(latestOrders),
  // A store sells in one currency, and it is usually not the user's. Totalled
  // in theirs, every row is excluded and the tile reads zero beside a list of
  // ten sales.
  totalIn: (ctx, items) => items.find((item) => item.currency)?.currency ?? ctx.preferredCurrency,
  note: (ctx, totalledIn) => currencyNote(totalledIn, ctx.preferredCurrency),
});

export const shopify = provider({
  manifest,
  credentialSchema,
  metrics: [revenue, orders, averageOrderValue, refunds, newCustomersMetric, customers, payments],
  verify: guarded(verifyToken),
});
