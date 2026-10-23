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

export const credentialSchema = z.object({
  api_key: z.string().min(20),
  mode: z.enum(["live", "sandbox"]).default("live"),
});
export type PaddleCredentials = z.infer<typeof credentialSchema>;

/**
 * The host is chosen by the declared mode, never inferred from the key.
 *
 * New keys do carry `pdl_live_` or `pdl_sdbx_`, but keys issued before
 * May 2025 are fifty opaque characters, and a wrong guess is a 403 that
 * reads as a revoked key.
 */
function host(creds: PaddleCredentials): string {
  return creds.mode === "sandbox" ? "sandbox-api.paddle.com" : "api.paddle.com";
}

/**
 * Transactions page at thirty, subscriptions at two hundred. Twenty pages of
 * the smaller one is six hundred transactions, which is a month of a busy
 * store; past that the walk stops and says so rather than running the
 * Worker out of time.
 */
const MAX_PAGES = 20;
const TRANSACTIONS_PAGE = 30;
const SUBSCRIPTIONS_PAGE = 200;

interface Page<T> {
  data: T[];
  meta?: { pagination?: { has_more?: boolean; next?: string | null } };
}

/** Paddle sends money as a string holding an integer in minor units: "2499". */
type Minor = string;

interface Subscription {
  id: string;
  status: string;
  currency_code: string;
  created_at: string;
  started_at?: string | null;
  canceled_at?: string | null;
  items: {
    status: string;
    quantity: number;
    recurring?: boolean;
    price: {
      unit_price: { amount: Minor; currency_code: string };
      billing_cycle?: { interval: string; frequency: number } | null;
    };
  }[];
}

interface Transaction {
  id: string;
  status: string;
  currency_code: string;
  billed_at?: string | null;
  created_at: string;
  customer?: { name?: string | null; email?: string | null } | null;
  details?: {
    totals?: { total?: Minor | null } | null;
    line_items?: { product?: { name?: string | null } | null }[] | null;
  } | null;
}

async function fetchJson<T>(ctx: AdapterContext, creds: PaddleCredentials, url: URL): Promise<T> {
  const response = await ctx.http(url.toString(), {
    headers: {
      authorization: `Bearer ${creds.api_key}`,
      // Pinned. Paddle's default version is a per-account setting, so an
      // unpinned request's shape depends on who connected it.
      "paddle-version": "1",
      accept: "application/json",
    },
  });
  if (!response.ok) throw errorForStatus(host(creds), response);
  return response.json<T>();
}

async function get<T>(
  ctx: AdapterContext,
  creds: PaddleCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  const url = new URL(`https://${host(creds)}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  return fetchJson<T>(ctx, creds, url);
}

/**
 * Follows `meta.pagination.next`, which Paddle sends with the original
 * filters already on it, until `has_more` is false or the page cap.
 *
 * `stopWhen` ends a walk early on an ordering the caller knows about —
 * transactions newest first stop at the first one older than the window.
 */
async function walk<T>(
  ctx: AdapterContext,
  creds: PaddleCredentials,
  path: string,
  params: Record<string, string | number | undefined>,
  stopWhen?: (row: T) => boolean,
): Promise<{ items: T[]; truncated: boolean }> {
  const items: T[] = [];
  let url = new URL(`https://${host(creds)}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }

  for (let page = 0; page < MAX_PAGES; page++) {
    const body = await fetchJson<Page<T>>(ctx, creds, url);
    for (const row of body.data ?? []) {
      if (stopWhen?.(row)) return { items, truncated: false };
      items.push(row);
    }
    const next = body.meta?.pagination?.next;
    if (!body.meta?.pagination?.has_more || !next) return { items, truncated: false };
    // Resolved against the current host, so a relative `next` — or one
    // pointing elsewhere — still goes through the allowlist check.
    url = new URL(next, url);
  }

  return { items, truncated: true };
}

/** "2499" → 2499. Anything that is not an integer string is a bad response, not zero. */
function minor(amount: Minor | null | undefined): number {
  if (amount === null || amount === undefined) return 0;
  if (!/^-?\d+$/.test(amount)) {
    throw new ProviderError("bad_response", `Paddle sent a non-integer amount: ${amount}`);
  }
  return Number(amount);
}

function truncationNote(truncated: boolean, what: string): string | undefined {
  return truncated
    ? `Only the first ${MAX_PAGES} pages of ${what} were read, so this is an undercount.`
    : undefined;
}

function join(...notes: (string | undefined)[]): string | undefined {
  const present = notes.filter((note): note is string => Boolean(note));
  return present.length ? present.join(" ") : undefined;
}

async function activeSubscriptions(ctx: AdapterContext, creds: PaddleCredentials) {
  return walk<Subscription>(ctx, creds, "/subscriptions", {
    status: "active",
    per_page: SUBSCRIPTIONS_PAGE,
  });
}

/**
 * A snapshot of the subscription book, not a total over a window.
 *
 * Each recurring item is price times quantity per cycle, normalised to a
 * month. Other currencies are excluded and named rather than summed at 1:1.
 */
async function mrrValue(ctx: AdapterContext, creds: PaddleCredentials): Promise<ScalarResult> {
  const { items, truncated } = await activeSubscriptions(ctx, creds);
  const want = ctx.preferredCurrency.toUpperCase();
  const others = new Set<string>();
  let total = 0;

  for (const subscription of items) {
    const code = subscription.currency_code.toUpperCase();
    if (code !== want) {
      others.add(code);
      continue;
    }
    for (const item of subscription.items) {
      const cycle = item.price.billing_cycle;
      if (!cycle || item.status !== "active") continue;
      total += toMonthly(
        minor(item.price.unit_price.amount) * (item.quantity ?? 1),
        cycle.interval,
        cycle.frequency ?? 1,
      );
    }
  }

  // Minor units are integers. Rounding once at the end rather than per
  // subscription keeps an annual plan's twelfth from drifting across a book.
  const value = Math.round(total);

  return {
    currency: ctx.preferredCurrency,
    value,
    note: join(
      others.size
        ? `${[...others].sort().join(" and ")} excluded; totals are ${want} only.`
        : undefined,
      truncationNote(truncated, "subscriptions"),
    ),
  };
}

async function activeCount(ctx: AdapterContext, creds: PaddleCredentials): Promise<ScalarResult> {
  const { items, truncated } = await activeSubscriptions(ctx, creds);
  return { value: items.length, note: truncationNote(truncated, "subscriptions") };
}

/** Transactions that took money. `billed` is an invoice awaiting payment. */
const PAID = new Set(["paid", "completed"]);

/** Paddle's time filters take RFC 3339 without a fractional second. */
function stamp(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

async function revenueOver(
  ctx: AdapterContext,
  creds: PaddleCredentials,
  request: MetricRequest,
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  const { items, truncated } = await walk<Transaction>(ctx, creds, "/transactions", {
    status: "paid,completed",
    "billed_at[GTE]": stamp(from),
    "billed_at[LTE]": stamp(request.to),
    order_by: "billed_at[DESC]",
    per_page: TRANSACTIONS_PAGE,
  });

  const want = ctx.preferredCurrency.toUpperCase();
  const others = new Set<string>();
  const events: { at: Date; amount: number }[] = [];
  for (const transaction of items) {
    if (!transaction.billed_at) continue;
    const code = transaction.currency_code.toUpperCase();
    if (code !== want) {
      others.add(code);
      continue;
    }
    events.push({
      at: new Date(transaction.billed_at),
      amount: minor(transaction.details?.totals?.total),
    });
  }

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
    points: request.wantSeries ? points : [],
    value,
    previousValue,
    note: join(
      others.size
        ? `${[...others].sort().join(" and ")} excluded; totals are ${want} only.`
        : undefined,
      truncationNote(truncated, "transactions"),
    ),
  };
}

/**
 * Subscriptions by when they started or were cancelled.
 *
 * Paddle's subscription list has no date filter and sorts by id only, so
 * the whole book is read and bucketed here. The page cap bounds it; a
 * store past the cap gets an undercount that says so.
 */
async function subscriptionEvents(
  ctx: AdapterContext,
  creds: PaddleCredentials,
  request: MetricRequest,
  field: "started_at" | "canceled_at",
): Promise<SeriesResult> {
  const windowMs = request.to.getTime() - request.from.getTime();
  const from = request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from;

  const { items, truncated } = await walk<Subscription>(ctx, creds, "/subscriptions", {
    per_page: SUBSCRIPTIONS_PAGE,
    ...(field === "canceled_at" ? { status: "canceled" } : {}),
  });

  const events = items
    .map(
      (subscription) =>
        subscription[field] ?? (field === "started_at" ? subscription.created_at : null),
    )
    .filter((at): at is string => Boolean(at))
    .map((at) => ({ at: new Date(at), amount: 1 }))
    .filter((event) => event.at >= from && event.at <= request.to);

  const points = bucketSum(events, {
    from: request.from,
    to: request.to,
    granularity: request.granularity,
    timeZone: ctx.timeZone,
  });
  const inWindow = (at: Date) => at >= request.from && at <= request.to;
  const value = events.filter((e) => inWindow(e.at)).length;
  const previousValue = request.comparePrevious
    ? events.filter((e) => !inWindow(e.at)).length
    : null;

  return {
    points: request.wantSeries ? points : [],
    value,
    previousValue,
    note: truncationNote(truncated, "subscriptions"),
  };
}

async function latestTransactions(
  ctx: AdapterContext,
  creds: PaddleCredentials,
): Promise<RawListItem[]> {
  const page = await get<Page<Transaction>>(ctx, creds, "/transactions", {
    status: "paid,completed",
    order_by: "billed_at[DESC]",
    per_page: Math.min(RECENT_PAYMENTS_LIMIT * 2, TRANSACTIONS_PAGE),
    // Embedded, so a list of ten does not become eleven requests.
    include: "customer",
  });
  const rows = (page.data ?? [])
    .filter((transaction) => PAID.has(transaction.status))
    .map((transaction) => ({
      id: transaction.id,
      t: new Date(transaction.billed_at ?? transaction.created_at),
      label: transaction.customer?.name || transaction.customer?.email || "Customer",
      detail: transaction.details?.line_items?.[0]?.product?.name ?? null,
      amount: minor(transaction.details?.totals?.total),
      currency: transaction.currency_code.toUpperCase(),
      status: transaction.status,
    }));
  // Sorted, capped and totalled by the shared payments metric.
  return rows;
}

const { scalar, series } = metricsFor<PaddleCredentials>();

export const mrr = scalar({
  id: "mrr",
  label: "Monthly recurring revenue",
  shortLabel: "MRR",
  unit: "currency",
  freshnessSeconds: 180,
  methodology:
    "Active subscriptions, each recurring item's unit price times quantity normalised to a month by its billing cycle. Discounts are not applied. A snapshot of the book right now.",
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
    "Transactions billed in the window that are paid or completed, by their total including tax, before Paddle's fee. Bucketed by billing date.",
  fetch: revenueOver,
});

export const activeSubscribers = scalar({
  id: "active_subscribers",
  label: "Active subscriptions",
  shortLabel: "Active",
  unit: "count",
  freshnessSeconds: 180,
  methodology: "Subscriptions in status `active` right now. Trialing and paused are not counted.",
  fetch: activeCount,
});

export const newSubscribers = series({
  id: "new_subscribers",
  label: "New subscriptions",
  shortLabel: "New",
  unit: "count",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 180,
  methodology:
    "Subscriptions whose `started_at` falls in the window, in any status. Paddle cannot filter subscriptions by date, so the whole list is read and bounded.",
  fetch: (ctx, creds, request) => subscriptionEvents(ctx, creds, request, "started_at"),
});

export const churnedSubscribers = series({
  id: "churned_subscribers",
  label: "Churned subscriptions",
  shortLabel: "Churn",
  unit: "count",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 180,
  methodology:
    "Subscriptions whose `canceled_at` falls in the window. Paddle cannot filter subscriptions by date, so the whole list is read and bounded.",
  fetch: (ctx, creds, request) => subscriptionEvents(ctx, creds, request, "canceled_at"),
});

export const payments = recentPaymentsMetric<PaddleCredentials>({
  methodology:
    "The latest paid or completed transactions by billing date, with the customer's name or email and the first product on the transaction. Totals include tax.",
  rows: latestTransactions,
});

export const paddle = provider({
  metrics: [mrr, revenue, activeSubscribers, newSubscribers, churnedSubscribers, payments],
  manifest,
  credentialSchema,

  async verify(ctx, creds) {
    // The cheapest authenticated call Paddle has: no permission, no paging.
    // Proves the key is real and on the right host before anything else.
    await get(ctx, creds, "/event-types");

    // Permissions are per entity. Narrowing to what the key can read beats
    // rejecting a key that was deliberately scoped down.
    // Said as what the key *cannot* read. `provider()` derives the available
    // set from the metrics, so this no longer restates them.
    const unavailableMetrics: MetricId[] = [];
    let currency: string | null = null;
    const permitted = async (probe: () => Promise<unknown>, grants: MetricId[]) => {
      try {
        await probe();
      } catch (error) {
        if (!(error instanceof ProviderError) || error.code !== "auth_failed") throw error;
        unavailableMetrics.push(...grants);
        ctx.log(`paddle key lacks a permission; not offering ${grants.join(", ")}`);
      }
    };
    await permitted(async () => {
      const page = await get<Page<Transaction>>(ctx, creds, "/transactions", { per_page: 1 });
      currency = page.data?.[0]?.currency_code?.toUpperCase() ?? null;
    }, ["revenue", "recent_payments"]);
    await permitted(
      () => get(ctx, creds, "/subscriptions", { per_page: 1 }),
      ["mrr", "active_subscribers", "new_subscribers", "churned_subscribers"],
    );

    if (unavailableMetrics.length === 6) {
      throw new ProviderError(
        "unsupported",
        "This key can read neither transactions nor subscriptions. Grant it read access to both.",
      );
    }

    return {
      // Paddle has no endpoint that names the seller, so the environment is
      // the only thing that tells two connections apart. The detail only —
      // the provider's name is added by `connectionName`.
      accountLabel: creds.mode === "sandbox" ? "Sandbox" : null,
      currency,
      unavailableMetrics,
    };
  },
});
