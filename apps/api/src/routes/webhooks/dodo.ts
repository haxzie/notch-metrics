import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { Webhook } from "standardwebhooks";
import { subscription, user, webhookEvent } from "@notch/db";
import { required, type Env } from "../../env.ts";
import type { AppContext } from "../../middleware.ts";
import { id } from "../../lib/ids.ts";
import { logError } from "../../lib/redact.ts";

/**
 * Dodo Payments webhooks. The only thing in this codebase that writes a plan.
 *
 * Dodo follows the Standard Webhooks spec: `webhook-id`, `webhook-signature`
 * and `webhook-timestamp` over the raw bytes.
 */
export const dodoWebhook = new Hono<AppContext>();

/** A failed renewal keeps access this long before the plan drops. */
const GRACE_DAYS = 3;

/**
 * Whether this delivery is about one of our products.
 *
 * The Dodo account is shared with other apps, so this endpoint receives their
 * subscriptions too. They were already harmless — `metadata.userId` is
 * written by our own checkout and nothing else sets it — but every foreign
 * delivery still consumed a `webhook_event` row and logged a warning, which
 * buries ours in somebody else's traffic.
 *
 * Deliberately only false when a product id is **present and not ours**. An
 * event without the field falls through to the `userId` gate rather than
 * being dropped: a field Dodo renames would otherwise silently discard real
 * upgrades, which is a far worse failure than the noise this removes.
 */
function isOurProduct(env: Env, event: DodoEvent): boolean {
  const productId = event.data?.product_id;
  if (!productId) return true;

  const ours = [env.DODOPAYMENT_MONTHLY_PRODUCT_ID, env.DODOPAYMENT_YEARLY_PRODUCT_ID].filter(
    (value): value is string => Boolean(value),
  );
  // Unconfigured means "cannot tell", which must not mean "reject everything".
  if (ours.length === 0) return true;
  return ours.includes(productId);
}

interface DodoEvent {
  type: string;
  data?: {
    product_id?: string;
    subscription_id?: string;
    customer?: { customer_id?: string; email?: string };
    metadata?: { userId?: string };
    status?: string;
    next_billing_date?: string;
    cancel_at_next_billing_date?: boolean;
  };
}

dodoWebhook.post("/", async (c) => {
  const secret = required(c.env, "DODOPAYMENT_WEBHOOK_SECRET");

  // The raw body, read once and never re-serialised. Parsing to JSON and
  // stringifying again changes whitespace and key order, and the signature is
  // over the exact bytes Dodo sent.
  const raw = await c.req.text();
  const headers = {
    "webhook-id": c.req.header("webhook-id") ?? "",
    "webhook-signature": c.req.header("webhook-signature") ?? "",
    "webhook-timestamp": c.req.header("webhook-timestamp") ?? "",
  };

  try {
    // `verify` also rejects a timestamp more than five minutes from now, which
    // is the replay guard — a captured delivery cannot be resent next week.
    new Webhook(secret).verify(raw, headers);
  } catch (error) {
    logError("webhooks.dodo.verify", error);
    return c.json({ code: "BAD_SIGNATURE", message: "Invalid signature." }, 401);
  }

  const event = JSON.parse(raw) as DodoEvent;

  // Before the idempotency insert, so another app's deliveries do not fill
  // this table with ids we will never look up. Still after verification, for
  // the reason below: an unsigned POST must not reach any write at all.
  if (!isOurProduct(c.env, event)) {
    // 200, not 4xx. A rejected delivery is one Dodo retries and eventually
    // flags the endpoint unhealthy for, and this one is not a failure: it is
    // simply not ours.
    return c.json({ ok: true, ignored: "product" });
  }

  const db = c.get("db");

  // The insert *is* the idempotency check. Dodo retries, and
  // `payment.succeeded` fires for renewals as well as first payments, so
  // "have I already handled this delivery?" is not optional.
  //
  // It happens strictly after verification: an unsigned POST must not be able
  // to insert an id and thereby suppress the real delivery that follows.
  const inserted = await db
    .insert(webhookEvent)
    .values({ id: headers["webhook-id"], type: event.type })
    .onConflictDoNothing()
    .returning({ id: webhookEvent.id });

  if (inserted.length === 0) return c.json({ ok: true, duplicate: true });

  const userId = event.data?.metadata?.userId;
  if (!userId) {
    // Acknowledged, not retried. Without our metadata there is nothing to
    // apply this to, and asking Dodo to resend it forever will not add one.
    console.warn(`[webhooks.dodo] ${event.type} carried no userId`);
    return c.json({ ok: true, ignored: true });
  }

  try {
    await apply(db, c.env.DODOPAYMENT_MODE, userId, event);
  } catch (error) {
    logError("webhooks.dodo.apply", error);
    // 500 so Dodo retries. The event id row is already written, so the retry
    // would be swallowed as a duplicate — remove it so the retry can work.
    await db.delete(webhookEvent).where(eq(webhookEvent.id, headers["webhook-id"]));
    return c.json({ code: "ERROR", message: "Could not apply." }, 500);
  }

  return c.json({ ok: true });
});

async function apply(
  db: import("../../lib/db.ts").Database,
  _mode: string,
  userId: string,
  event: DodoEvent,
): Promise<void> {
  const data = event.data ?? {};
  const now = new Date();

  const base = {
    dodoSubscriptionId: data.subscription_id ?? null,
    dodoCustomerId: data.customer?.customer_id ?? null,
    currentPeriodEnd: data.next_billing_date ? new Date(data.next_billing_date) : null,
    cancelAtPeriodEnd: data.cancel_at_next_billing_date ?? false,
    updatedAt: now,
  };

  const upsert = async (status: string, graceUntil: Date | null) => {
    await db
      .insert(subscription)
      .values({ id: id("sub"), userId, status, graceUntil, ...base })
      .onConflictDoUpdate({
        target: subscription.userId,
        set: { status, graceUntil, ...base },
      });
  };

  switch (event.type) {
    case "subscription.active":
    case "subscription.renewed":
      await upsert("active", null);
      await db.update(user).set({ plan: "pro" }).where(eq(user.id, userId));
      break;

    case "subscription.on_hold":
    case "subscription.failed":
      // Keep access through the grace window. A card that expires on a Friday
      // should not blank somebody's dashboard over the weekend.
      await upsert("past_due", new Date(now.getTime() + GRACE_DAYS * 24 * 3600 * 1000));
      break;

    case "subscription.cancelled":
      await upsert("cancelled", null);
      // Deliberately not dropping the plan here. A cancellation usually means
      // "do not renew"; `currentPeriodEnd` is what the cron watches, and
      // cutting access the moment somebody cancels is a refund request.
      break;

    case "subscription.expired":
      await upsert("expired", null);
      await db.update(user).set({ plan: "expired" }).where(eq(user.id, userId));
      break;

    default:
      break;
  }
}
