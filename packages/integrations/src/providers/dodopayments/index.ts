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
  mode: z.enum(["test", "live"]).default("live"),
});
export type DodoCredentials = z.infer<typeof credentialSchema>;

/**
 * The host is chosen by the declared mode, never inferred from the key.
 *
 * A live key against the test host answers 401, which reads as a bad key
 * rather than the wrong host and costs an hour before anyone suspects it.
 */
function baseUrl(creds: DodoCredentials): string {
  return creds.mode === "test" ? "https://test.dodopayments.com" : "https://live.dodopayments.com";
}

function host(creds: DodoCredentials): string {
  return creds.mode === "test" ? "test.dodopayments.com" : "live.dodopayments.com";
}

const MAX_PAGES = 20;
const PAGE_SIZE = 100;

/** Dodo answers `{ items: [...] }` with no cursor and no total. */
interface DodoList<T> {
  items: T[];
}

async function get<T>(
  ctx: AdapterContext,
  creds: DodoCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  const url = new URL(`${baseUrl(creds)}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  const response = await ctx.http(url.toString(), {
    headers: { authorization: `Bearer ${creds.api_key}` },
  });
  if (!response.ok) throw errorForStatus(host(creds), response);
  return response.json<T>();
}

/**
 * One row of a list, or the fact that this key may not read it.
 *
 * 403 and 401 are different answers from Dodo: 401 is a key it does not
 * know, 403 is a key it knows that lacks the scope for this resource.
 * `errorForStatus` folds both into `auth_failed`, which is right for a
 * metric fetch and wrong here, where the scope decides what to offer.
 */
async function probe<T extends { currency: string }>(
  ctx: AdapterContext,
  creds: DodoCredentials,
  path: string,
): Promise<{ allowed: boolean; first: T | undefined }> {
  const url = new URL(`${baseUrl(creds)}${path}`);
  url.searchParams.set("page_size", "1");
  url.searchParams.set("page_number", "0");
  const response = await ctx.http(url.toString(), {
    headers: { authorization: `Bearer ${creds.api_key}` },
  });
  if (response.status === 403) return { allowed: false, first: undefined };
  if (!response.ok) throw errorForStatus(host(creds), response);
  const body = await response.json<DodoList<T>>();
  return { allowed: true, first: body.items?.[0] };
}

/**
 * Walks `page_number` until a short page.
 *
 * Termination is on the page being shorter than `page_size`, because Dodo
 * sends no cursor and no `has_more`. A `while (true)` waiting for a cursor
 * field Dodo never sends is an infinite loop inside a Worker.
 */
async function walk<T>(
  ctx: AdapterContext,
  creds: DodoCredentials,
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<{ items: T[]; truncated: boolean }> {
  const items: T[] = [];

  for (let page = 0; page < MAX_PAGES; page++) {
    const body = await get<DodoList<T>>(ctx, creds, path, {
      ...params,
      page_number: page,
      page_size: PAGE_SIZE,
    });
    const batch = body.items ?? [];
    items.push(...batch);
    if (batch.length < PAGE_SIZE) return { items, truncated: false };
  }

  return { items, truncated: true };
}

interface DodoSubscription {
  subscription_id: string;
  status: string;
  recurring_pre_tax_amount: number;
  currency: string;
  payment_frequency_interval: string;
  payment_frequency_count: number;
  created_at: string;
  cancelled_at?: string | null;
}

interface DodoPayment {
  payment_id: string;
  total_amount: number;
  currency: string;
  status: string;
  created_at: string;
  customer?: { name?: string | null; email?: string | null } | null;
  /** Null for a one-time purchase. */
  subscription_id?: string | null;
  /** Set alongside `subscription_id` when one checkout bought several. */
  subscription_ids?: string[] | null;
}

/**
 * A payment with no subscription behind it.
 *
 * Both fields, because Dodo added `subscription_ids` for multi-subscription
 * checkouts and a payment can carry either. Checking only the singular would
 * count a bundle renewal as a one-time sale.
 */
function isOneTime(payment: DodoPayment): boolean {
  return !payment.subscription_id && !(payment.subscription_ids?.length ?? 0);
}

/**
 * Only the currencies the user asked for.
 *
 * Summing mixed currencies at 1:1 is the kind of wrong that looks right, so
 * other currencies are dropped and the exclusion is named in the note.
 */
function splitByCurrency<T extends { currency: string }>(
  rows: T[],
  preferred: string,
): { kept: T[]; note?: string } {
  const kept = rows.filter((row) => row.currency.toUpperCase() === preferred.toUpperCase());
  const others = new Set(
    rows
      .map((row) => row.currency.toUpperCase())
      .filter((code) => code !== preferred.toUpperCase()),
  );
  if (others.size === 0) return { kept };
  return {
    kept,
    note: `${[...others].sort().join(" and ")} excluded; totals are ${preferred.toUpperCase()} only.`,
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

/**
 * A snapshot of the subscription book, not a total over a window.
 *
 * `value` is deliberately not `sum(points)` here — MRR is what the book is
 * worth right now, and there is a single point because Dodo exposes no
 * history of it.
 */
async function mrrValue(ctx: AdapterContext, creds: DodoCredentials): Promise<ScalarResult> {
  const { items, truncated } = await walk<DodoSubscription>(ctx, creds, "/subscriptions", {
    status: "active",
  });
  const { kept, note } = splitByCurrency(items, ctx.preferredCurrency);

  const total = kept.reduce(
    (sum, row) =>
      sum +
      toMonthly(
        row.recurring_pre_tax_amount,
        // Dodo capitalises these ("Month"), toMonthly expects lower case.
        row.payment_frequency_interval.toLowerCase(),
        row.payment_frequency_count,
      ),
    0,
  );

  // Minor units are integers. Rounding once at the end rather than per
  // subscription keeps an annual plan's twelfth from drifting across a book.
  const value = Math.round(total);

  return { currency: ctx.preferredCurrency, value, note: join(note, truncationNote(truncated)) };
}

async function activeCount(ctx: AdapterContext, creds: DodoCredentials): Promise<ScalarResult> {
  const { items, truncated } = await walk<DodoSubscription>(ctx, creds, "/subscriptions", {
    status: "active",
  });

  return { value: items.length, note: truncationNote(truncated) };
}

/**
 * Succeeded payments in the window, summed — optionally only those `include`
 * says yes to. Total revenue and one-time sales are the same walk with a
 * different filter; the list has no server-side way to ask for either.
 */
async function revenueOver(
  ctx: AdapterContext,
  creds: DodoCredentials,
  request: MetricRequest,
  include: (payment: DodoPayment) => boolean,
): Promise<SeriesResult> {
  const from = request.comparePrevious
    ? new Date(request.from.getTime() - (request.to.getTime() - request.from.getTime()))
    : request.from;

  const { items, truncated } = await walk<DodoPayment>(ctx, creds, "/payments", {
    created_at_gte: from.toISOString(),
    created_at_lte: request.to.toISOString(),
  });

  // Gross, and only money that actually arrived. `processing` has not been
  // captured and `requires_capture` may never be.
  const succeeded = items.filter((row) => row.status === "succeeded" && include(row));
  const { kept, note } = splitByCurrency(succeeded, ctx.preferredCurrency);

  const events = kept.map((row) => ({ at: new Date(row.created_at), amount: row.total_amount }));
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

/**
 * The newest payments that actually took money. Dodo lists newest first, so
 * one page over-fetched by a factor of two covers a run of failed attempts.
 */
async function latestPayments(ctx: AdapterContext, creds: DodoCredentials): Promise<RawListItem[]> {
  const body = await get<DodoList<DodoPayment>>(ctx, creds, "/payments", {
    page_size: RECENT_PAYMENTS_LIMIT * 2,
    page_number: 0,
  });
  const rows = (body.items ?? [])
    .filter((payment) => payment.status === "succeeded")
    .map((payment) => ({
      id: payment.payment_id,
      t: new Date(payment.created_at),
      label: payment.customer?.name || payment.customer?.email || "Customer",
      detail: null,
      amount: payment.total_amount,
      currency: payment.currency.toUpperCase(),
      status: payment.status,
    }));
  // Sorted, capped and totalled by `recentPaymentsMetric`, shared with the
  // other payment connectors.
  return rows;
}

const { scalar, series } = metricsFor<DodoCredentials>();

export const mrr = scalar({
  id: "mrr",
  label: "Monthly recurring revenue",
  shortLabel: "MRR",
  unit: "currency",
  freshnessSeconds: 180,
  methodology:
    "Active subscriptions, each `recurring_pre_tax_amount` normalised to a monthly amount using its payment frequency. A snapshot of the book right now, not a total over the window.",
  fetch: mrrValue,
});

export const revenue = series({
  id: "revenue",
  label: "Total revenue",
  shortLabel: "Revenue",
  unit: "currency",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Every succeeded payment in the window, subscription renewals and one-time purchases together, by `total_amount`. Gross, before refunds and fees.",
  fetch: (ctx, creds, request) => revenueOver(ctx, creds, request, () => true),
});

export const oneTimeSales = series({
  id: "one_time_sales",
  label: "One-time sales",
  shortLabel: "One-time",
  unit: "currency",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 60,
  methodology:
    "Succeeded payments in the window that are not tied to a subscription, by `total_amount`. Gross, before refunds and fees.",
  // The same walk as revenue with a different filter: the list has no
  // server-side way to ask for either.
  fetch: (ctx, creds, request) => revenueOver(ctx, creds, request, isOneTime),
});

export const activeSubscribers = scalar({
  id: "active_subscribers",
  label: "Active subscribers",
  shortLabel: "Active",
  unit: "count",
  freshnessSeconds: 180,
  methodology: "Subscriptions in status `active` right now.",
  fetch: activeCount,
});

export const payments = recentPaymentsMetric<DodoCredentials>({
  methodology:
    "The latest succeeded payments, newest first, with the customer's name or email. The headline is their total in your currency.",
  rows: latestPayments,
});

export const dodopayments = provider({
  metrics: [mrr, revenue, oneTimeSales, activeSubscribers, payments],
  manifest,
  credentialSchema,

  async verify(ctx, creds) {
    // There is no `/me` on this API, so the proof that the key works against
    // this host is a one-row list — and Dodo keys carry scopes per resource,
    // so each list is probed on its own. A key with `payments:read` and no
    // `subscriptions:read` is a perfectly good key for revenue; rejecting it
    // outright told somebody their key was wrong when it was merely narrow.
    const payments = await probe<DodoPayment>(ctx, creds, "/payments");
    const subscriptions = await probe<DodoSubscription>(ctx, creds, "/subscriptions");

    // Said as what this key *cannot* read. `provider()` derives the available
    // set from the metrics, so this is no longer a second copy of them.
    const unavailableMetrics: MetricId[] = [];
    if (!payments.allowed) {
      unavailableMetrics.push("revenue", "one_time_sales", "recent_payments");
    }
    if (!subscriptions.allowed) unavailableMetrics.push("mrr", "active_subscribers");
    if (!payments.allowed && !subscriptions.allowed) {
      throw new ProviderError(
        "unsupported",
        "This key can read neither payments nor subscriptions. Give it payments:read and subscriptions:read.",
      );
    }
    if (!subscriptions.allowed) {
      ctx.log("dodo key lacks subscriptions:read; offering revenue and payments only");
    }

    const currency = subscriptions.first?.currency ?? payments.first?.currency ?? null;

    return {
      // The API exposes no account or business name, so the mode is the only
      // thing that distinguishes two connections. The detail only — the
      // provider's name is added by `connectionName`.
      accountLabel: creds.mode === "test" ? "Test" : null,
      currency: currency?.toUpperCase() ?? null,
      unavailableMetrics,
    };
  },
});
