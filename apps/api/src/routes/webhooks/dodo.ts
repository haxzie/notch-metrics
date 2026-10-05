import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { Webhook } from "standardwebhooks";
import { subscription, user, webhookEvent } from "@notch/db";
import { required } from "../../env.ts";
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

interface DodoEvent {
  type: string;
  data?: {
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
