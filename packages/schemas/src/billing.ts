import { z } from "zod";

/**
 * There is no free tier. A new account gets a seven-day trial and then needs
 * the one-off purchase for any metric to load.
 *
 * `pro` is a lifetime licence rather than a subscription now, so nothing
 * renews and nothing lapses once it is bought. `expired` therefore only ever
 * means a trial that ran out unpaid.
 */
export const Plan = z.enum(["trial", "pro", "expired"]);
export type Plan = z.infer<typeof Plan>;

export const SubscriptionStatus = z.enum([
  "trialing",
  "active",
  "past_due",
  "cancelled",
  "expired",
]);
export type SubscriptionStatus = z.infer<typeof SubscriptionStatus>;

export const BillingState = z.object({
  plan: Plan,
  status: SubscriptionStatus,
  trialEndsAt: z.string().nullable(),
  currentPeriodEnd: z.string().nullable(),
  /** A failed renewal keeps access until here before the plan drops. */
  graceUntil: z.string().nullable(),
  cancelAtPeriodEnd: z.boolean(),
  hasCustomer: z.boolean(),
});
export type BillingState = z.infer<typeof BillingState>;

export const CheckoutRequest = z.object({
  // One plan, and kept as an enum so adding a second is a schema change
  // rather than a string appearing in a request body.
  plan: z.enum(["pro"]).default("pro"),
});
export type CheckoutRequest = z.infer<typeof CheckoutRequest>;

export const CheckoutResponse = z.object({ url: z.url() });
export type CheckoutResponse = z.infer<typeof CheckoutResponse>;

/**
 * How often a plan is paid for. `lifetime` is paid once and never again,
 * which is the only option today.
 *
 * Kept as an enum rather than dropped: the word reaches the pricing page and
 * the checkout, and "lifetime" is a promise worth being able to change
 * deliberately rather than by editing a string.
 */
export const BillingInterval = z.enum(["lifetime"]);
export type BillingInterval = z.infer<typeof BillingInterval>;

export interface PlanOption {
  id: "pro";
  interval: BillingInterval;
  /** Minor units, as everywhere else. A price is money and money is not a float. */
  amount: number;
  currency: string;
}

/**
 * Prices live here rather than on the pricing page so the website, the
 * checkout and the desktop upsell cannot drift. Dodo holds the authoritative
 * amount — these are for display and must be changed together with the
 * product in the Dodo dashboard.
 */
export const PLANS: Record<"pro", PlanOption> = {
  pro: { id: "pro", interval: "lifetime", amount: 500, currency: "USD" },
};

/** `500` → `"$5"`. Whole amounts lose the `.00`. */
export function formatPrice(amount: number, currency: string, locale = "en-US"): string {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    minimumFractionDigits: amount % 100 === 0 ? 0 : 2,
  }).format(amount / 100);
}

/** The price, formatted, for the one plan there is. */
export function proPrice(locale = "en-US"): string {
  return formatPrice(PLANS.pro.amount, PLANS.pro.currency, locale);
}
