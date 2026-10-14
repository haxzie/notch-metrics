import type { MetricDescriptor } from "@notch/schemas";
import type { AdapterContext, RawListItem, RawSeries } from "./types.ts";

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
