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
