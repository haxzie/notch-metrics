import { z } from "zod";
import type { MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { bucketSum, toMonthly } from "../../normalise.ts";
import type {
  AdapterContext,
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

export const dodopayments: ProviderAdapter<DodoCredentials> = {
  manifest,
  credentialSchema,

  async verify(ctx, creds): Promise<VerifyResult> {
    // There is no `/me` on this API, so the cheapest proof that the key works
    // against this host is a one-row list.
    const body = await get<DodoList<DodoSubscription>>(ctx, creds, "/subscriptions", {
      page_size: 1,
      page_number: 0,
    });

    const available: MetricId[] = ["mrr", "revenue", "active_subscribers"];
    const first = body.items?.[0];

    return {
      // The API exposes no account or business name, so the mode is the only
      // thing that distinguishes two connections in a list. Saying "live" or
      // "test" is more use than repeating "Dodo Payments" twice.
      accountLabel: creds.mode === "test" ? "Dodo Payments (test)" : "Dodo Payments",
      currency: first?.currency?.toUpperCase() ?? null,
      availableMetrics: available,
    };
  },

  async fetchMetric(ctx, creds, request): Promise<RawSeries> {
    switch (request.metric) {
      case "mrr":
        return mrr(ctx, creds);
      case "active_subscribers":
        return activeSubscribers(ctx, creds);
      case "revenue":
        return revenue(ctx, creds, request);
      default:
        throw new ProviderError("unsupported", `Dodo Payments does not provide ${request.metric}.`);
    }
  },
};

/**
 * A snapshot of the subscription book, not a total over a window.
 *
 * `value` is deliberately not `sum(points)` here — MRR is what the book is
 * worth right now, and there is a single point because Dodo exposes no
 * history of it.
 */
async function mrr(ctx: AdapterContext, creds: DodoCredentials): Promise<RawSeries> {
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

  return {
    unit: "currency",
    currency: ctx.preferredCurrency,
    points: [{ t: ctx.now(), v: value }],
    value,
    previousValue: null,
    asOf: ctx.now(),
    note: join(note, truncationNote(truncated)),
  };
}

async function activeSubscribers(ctx: AdapterContext, creds: DodoCredentials): Promise<RawSeries> {
  const { items, truncated } = await walk<DodoSubscription>(ctx, creds, "/subscriptions", {
    status: "active",
  });

  return {
    unit: "count",
    currency: null,
    points: [{ t: ctx.now(), v: items.length }],
    value: items.length,
    previousValue: null,
    asOf: ctx.now(),
    note: truncationNote(truncated),
  };
}

async function revenue(
  ctx: AdapterContext,
  creds: DodoCredentials,
  request: MetricRequest,
): Promise<RawSeries> {
  const from = request.comparePrevious
    ? new Date(request.from.getTime() - (request.to.getTime() - request.from.getTime()))
    : request.from;

  const { items, truncated } = await walk<DodoPayment>(ctx, creds, "/payments", {
    created_at_gte: from.toISOString(),
    created_at_lte: request.to.toISOString(),
  });

  // Gross, and only money that actually arrived. `processing` has not been
  // captured and `requires_capture` may never be.
  const succeeded = items.filter((row) => row.status === "succeeded");
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
    unit: "currency",
    currency: ctx.preferredCurrency,
    points,
    value,
    previousValue,
    note: join(note, truncationNote(truncated)),
  };
}
