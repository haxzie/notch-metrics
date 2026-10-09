import { z } from "zod";

/**
 * There is no free tier. A new account gets a seven-day trial and then needs a
 * subscription for any metric to load.
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
  plan: z.enum(["pro", "pro_annual"]).default("pro"),
});
export type CheckoutRequest = z.infer<typeof CheckoutRequest>;

export const CheckoutResponse = z.object({ url: z.url() });
export type CheckoutResponse = z.infer<typeof CheckoutResponse>;

/** The two ways to pay. `id` is what `POST /v1/billing/checkout` expects. */
export const BillingInterval = z.enum(["month", "year"]);
export type BillingInterval = z.infer<typeof BillingInterval>;

export interface PlanOption {
  id: "pro" | "pro_annual";
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
export const PLANS: Record<"pro" | "pro_annual", PlanOption> = {
  pro: { id: "pro", interval: "month", amount: 1400, currency: "USD" },
  pro_annual: { id: "pro_annual", interval: "year", amount: 7900, currency: "USD" },
};

/** `1400` → `"$14"`, and `7900` → `"$79"`. Whole amounts lose the `.00`. */
export function formatPrice(amount: number, currency: string, locale = "en-US"): string {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    minimumFractionDigits: amount % 100 === 0 ? 0 : 2,
  }).format(amount / 100);
}

/** What the annual plan saves against twelve monthly payments, as a percent. */
export function annualSavingPercent(): number {
  const yearOfMonths = PLANS.pro.amount * 12;
  return Math.round(((yearOfMonths - PLANS.pro_annual.amount) / yearOfMonths) * 100);
}
