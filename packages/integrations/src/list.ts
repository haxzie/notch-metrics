import type { MetricDescriptor } from "@notch/schemas";
import { listMetric, type MetricDefinition } from "./metric.ts";
import type { AdapterContext, MetricRequest, RawListItem, RawSeries } from "./types.ts";

/**
 * How many rows a list widget carries.
 *
 * Ten is what the tallest tile can show, and a list is a glance at what just
 * happened, not a ledger — the provider's dashboard is one click away for
 * the rest. Fetching more would also mean walking pages on every poll.
 */
export const RECENT_PAYMENTS_LIMIT = 10;

/**
 * The descriptor every payment provider shares for its payments feed.
 *
 * One definition rather than five copies: the label and the flags have to
 * agree across providers or the gallery shows the same widget under two
 * names. Only the methodology is the provider's own, because what counts as
 * a payment is.
 */
export function recentPaymentsDescriptor(methodology: string): MetricDescriptor {
  return {
    id: "recent_payments",
    label: "Recent payments",
    shortLabel: "Payments",
    unit: "currency",
    granularities: ["day"],
    // A feed of the latest rows has no window: it is the same ten payments
    // whatever the range says, so neither a chart nor a comparison applies.
    supportsSeries: false,
    supportsCompare: false,
    // The fastest the floor allows. A payment is an event rather than a
    // figure: it exists the moment it settles, and a feed of them is the one
    // tile somebody watches *because* it changes. Held for the daily bucket's
    // fifteen minutes it would show a sale a quarter of an hour after the
    // money arrived, which is the whole thing it is for.
    freshnessSeconds: 60,
    methodology,
  };
}

/**
 * Builds the series for a payments feed.
 *
 * The rows are the point. The headline is their total in the user's
 * currency, so a tile too short to show rows still says something true —
 * and rows in another currency are listed with their own code rather than
 * dropped, because a list can show a currency where a sum cannot.
 */
export function recentPayments(ctx: AdapterContext, rows: RawListItem[]): RawSeries {
  const items = [...rows]
    .sort((a, b) => b.t.getTime() - a.t.getTime())
    .slice(0, RECENT_PAYMENTS_LIMIT);

  const want = ctx.preferredCurrency.toUpperCase();
  const value = items.reduce(
    (sum, item) =>
      item.amount !== null && item.currency?.toUpperCase() === want ? sum + item.amount : sum,
    0,
  );

  return {
    unit: "currency",
    currency: ctx.preferredCurrency,
    points: [{ t: ctx.now(), v: value }],
    value,
    previousValue: null,
    asOf: ctx.now(),
    items,
  };
}

/**
 * The payments feed as one metric, shared by every payment provider.
 *
 * `recentPaymentsDescriptor` and `recentPayments` were the two halves of
 * this: a descriptor each provider spread into its manifest and a builder
 * each called from its own `case`, with nothing holding the two together.
 * Both are still exported — the builder because Shopify's currency handling
 * reaches for it, the descriptor because this is built from it and
 * `list.test.ts` pins its flags — but a provider wants this.
 *
 * A provider supplies only `rows`. The sort, the cap and the headline total
 * are the shared half, and they are the half worth not having six copies of:
 * the total is the rows in the user's own currency, which is not
 * `items.length` and is the one thing a provider could plausibly get wrong
 * on its own.
 */
export function recentPaymentsMetric<C extends Record<string, unknown>>(options: {
  methodology: string;
  rows: (ctx: AdapterContext, credentials: C, request: MetricRequest) => Promise<RawListItem[]>;
  /**
   * The currency the headline is totalled in, when it is not the user's.
   *
   * A Shopify store sells in exactly one currency, which is usually not the
   * one the user asked the notch for — and totalling in theirs filters every
   * row out and shows zero against a list of ten sales. So the store's own
   * currency wins there, and `note` says so.
   *
   * Defaulted rather than required because for every other provider the
   * user's currency is the right one: the rows are a mixed book and a sum of
   * two currencies is not a number.
   */
  totalIn?: (ctx: AdapterContext, items: RawListItem[]) => string;
  /** Said alongside the figure, e.g. that the total is in another currency. */
  note?: (ctx: AdapterContext, totalledIn: string) => string | undefined;
}): MetricDefinition<C> {
  const descriptor = recentPaymentsDescriptor(options.methodology);
  return listMetric<C>({
    id: "recent_payments",
    label: descriptor.label,
    shortLabel: descriptor.shortLabel,
    unit: "currency",
    limit: RECENT_PAYMENTS_LIMIT,
    freshnessSeconds: descriptor.freshnessSeconds,
    methodology: options.methodology,

    async fetch(ctx, credentials, request) {
      const rows = await options.rows(ctx, credentials, request);
      const currency = options.totalIn?.(ctx, rows) ?? ctx.preferredCurrency;
      const series = recentPayments({ ...ctx, preferredCurrency: currency }, rows);
      const note = options.note?.(ctx, currency);
      // `value` is explicit because it is not the row count: a feed too short
      // to show rows still has to say something true, and that is their total
      // in one currency.
      return {
        items: series.items ?? [],
        value: series.value,
        currency: series.currency,
        ...(note !== undefined ? { note } : {}),
      };
    },
  });
}
