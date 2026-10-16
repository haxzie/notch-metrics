import type { BillingState, Plan, SubscriptionStatus } from "@notch/schemas";
import { eq } from "drizzle-orm";
import { subscription, user } from "@notch/db";
import type { Database } from "./db.ts";

export const TRIAL_DAYS = 7;

/**
 * The billing facts for a user. Facts, not a verdict.
 *
 * `/v1/desktop/entitlement` returns this rather than a boolean, because the
 * moment both sides of the wire compute "is this user allowed" independently,
 * the two answers diverge the first time either changes — and the one that
 * matters is whichever the Worker applies.
 */
export async function billingState(db: Database, userId: string): Promise<BillingState> {
  const [u] = await db
    .select({ plan: user.plan, trialEndsAt: user.trialEndsAt })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);

  const [sub] = await db
    .select()
    .from(subscription)
    .where(eq(subscription.userId, userId))
    .limit(1);

  const trialEndsAt = u?.trialEndsAt ?? null;
  // A trial that has run out is `expired`, not `trialing`.
  //
  // Any non-null `trialEndsAt` used to read as `trialing` whatever the date
  // said, so an account whose trial had lapsed reported itself as still on
  // one. `hasAccess` was right either way — it compares the date — but every
  // consumer of these facts was being told the opposite of the verdict, and
  // the billing page rendered it literally: "Your trial runs until", past
  // tense date, next to an API answering 402.
  const trialing = trialEndsAt !== null && trialEndsAt.getTime() > Date.now();
  const status = (sub?.status ?? (trialing ? "trialing" : "expired")) as SubscriptionStatus;

  return {
    plan: (u?.plan ?? "expired") as Plan,
    status,
    trialEndsAt: trialEndsAt?.toISOString() ?? null,
    currentPeriodEnd: sub?.currentPeriodEnd?.toISOString() ?? null,
    graceUntil: sub?.graceUntil?.toISOString() ?? null,
    cancelAtPeriodEnd: sub?.cancelAtPeriodEnd ?? false,
    hasCustomer: Boolean(sub?.dodoCustomerId),
  };
}

/**
 * There is no free tier: a seven-day trial, then a subscription.
 *
 * A failed renewal keeps access until `graceUntil` so a card that expires on a
 * Friday does not blank somebody's dashboard over the weekend.
 */
export function hasAccess(state: BillingState, now = new Date()): boolean {
  if (state.plan === "pro" && (state.status === "active" || state.status === "trialing")) {
    return true;
  }
  if (state.graceUntil && new Date(state.graceUntil) > now) return true;
  if (state.plan === "trial" && state.trialEndsAt && new Date(state.trialEndsAt) > now) {
    return true;
  }
  return false;
}
