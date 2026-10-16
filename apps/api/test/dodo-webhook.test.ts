import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { Webhook } from "standardwebhooks";
import { subscription, user, webhookEvent } from "@notch/db";
import worker from "../src/index.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(webhookEvent);
  await db().delete(subscription);
  await db().delete(user);
});

const ctx = createExecutionContext();
const SECRET = "whsec_dGVzdHNlY3JldGZvcnNpZ25pbmd0ZXN0cw==";

function deliver(payload: unknown, options: { id?: string; at?: Date; tamper?: boolean } = {}) {
  const webhookId = options.id ?? `msg_${crypto.randomUUID()}`;
  const timestamp = options.at ?? new Date();
  const body = JSON.stringify(payload);
  const signature = new Webhook(SECRET).sign(webhookId, timestamp, body);

  return worker.fetch(
    new Request("http://localhost:8787/v1/webhooks/dodo", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "webhook-id": webhookId,
        "webhook-signature": signature,
        "webhook-timestamp": String(Math.floor(timestamp.getTime() / 1000)),
      },
      body: options.tamper ? `${body} ` : body,
    }),
    env,
    ctx,
  );
}

const activeEvent = (userId: string) => ({
  type: "subscription.active",
  data: {
    subscription_id: "sub_123",
    customer: { customer_id: "cus_123", email: "a@example.com" },
    metadata: { userId },
    next_billing_date: "2026-11-05T00:00:00Z",
  },
});

describe("signature verification", () => {
  it("accepts a correctly signed delivery and upgrades the plan", async () => {
    const u = await makeUser({ plan: "trial" });
    expect((await deliver(activeEvent(u.id))).status).toBe(200);

    const [row] = await db().select().from(user).where(eq(user.id, u.id));
    expect(scalar(row, "user").plan).toBe("pro");

    const [sub] = await db().select().from(subscription).where(eq(subscription.userId, u.id));
    expect(scalar(sub, "subscription").status).toBe("active");
  });

  it("rejects a tampered body with 401 and writes no event row", async () => {
    // The event row must be written strictly *after* verification. If an
    // unsigned POST could insert an id, it would suppress the real delivery
    // that followed as a duplicate — a denial of service on somebody's upgrade.
    const u = await makeUser({ plan: "trial" });
    const webhookId = "msg_forged";

    const response = await deliver(activeEvent(u.id), { id: webhookId, tamper: true });
    expect(response.status).toBe(401);

    const rows = await db().select().from(webhookEvent).where(eq(webhookEvent.id, webhookId));
    expect(rows).toHaveLength(0);

    const [row] = await db().select().from(user).where(eq(user.id, u.id));
    expect(scalar(row, "user").plan).toBe("trial");
  });

  it("rejects a replay from outside the timestamp window", async () => {
    const u = await makeUser();
    const old = new Date(Date.now() - 10 * 60 * 1000);
    expect((await deliver(activeEvent(u.id), { at: old })).status).toBe(401);
  });
});

describe("idempotency", () => {
  it("applies a delivery once and reports the retry as a duplicate", async () => {
    const u = await makeUser({ plan: "trial" });
    const webhookId = "msg_once";

    const first = await deliver(activeEvent(u.id), { id: webhookId });
    const second = await deliver(activeEvent(u.id), { id: webhookId });

    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ ok: true });
    expect(second.status).toBe(200);
    expect(await second.json()).toEqual({ ok: true, duplicate: true });
  });
});

describe("lifecycle", () => {
  it("keeps access through a grace window when a renewal fails", async () => {
    const u = await makeUser();
    await deliver(activeEvent(u.id));
    await deliver({
      type: "subscription.on_hold",
      data: { subscription_id: "sub_123", metadata: { userId: u.id } },
    });

    const [sub] = await db().select().from(subscription).where(eq(subscription.userId, u.id));
    const row = scalar(sub, "subscription");
    expect(row.status).toBe("past_due");
    // A card expiring on a Friday should not blank somebody's dashboard over
    // the weekend.
    const graceUntil = scalar(row.graceUntil ?? undefined, "graceUntil");
    expect(graceUntil.getTime()).toBeGreaterThan(Date.now());
  });

  it("drops the plan only on expiry, not on cancellation", async () => {
    const u = await makeUser();
    await deliver(activeEvent(u.id));

    await deliver({
      type: "subscription.cancelled",
      data: { subscription_id: "sub_123", metadata: { userId: u.id } },
    });
    let [row] = await db().select().from(user).where(eq(user.id, u.id));
    // "Cancel" means "do not renew". Cutting access the moment somebody
    // cancels is a refund request.
    expect(scalar(row, "user").plan).toBe("pro");

    await deliver({
      type: "subscription.expired",
      data: { subscription_id: "sub_123", metadata: { userId: u.id } },
    });
    [row] = await db().select().from(user).where(eq(user.id, u.id));
    expect(scalar(row, "user").plan).toBe("expired");
  });

  it("acknowledges an event with no userId rather than retrying forever", async () => {
    const response = await deliver({ type: "subscription.active", data: {} });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, ignored: true });
  });
});

describe("other apps in the same Dodo account", () => {
  /**
   * The account is shared, so this endpoint receives subscriptions belonging
   * to products that are nothing to do with Notch Metrics.
   */
  it("acknowledges another product's event without touching anything", async () => {
    const u = await makeUser({ plan: "trial" });
    const foreign = {
      ...activeEvent(u.id),
      data: { ...activeEvent(u.id).data, product_id: "pdt_someotherapp" },
    };

    const response = await deliver(foreign);
    // 200, not 4xx: a rejected delivery is one Dodo retries and eventually
    // flags the endpoint unhealthy over, and this is not a failure.
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ignored: "product" });

    // Untouched, and no idempotency row consumed on somebody else's behalf.
    expect(scalar((await db().select().from(user).where(eq(user.id, u.id)))[0], "user").plan).toBe(
      "trial",
    );
    expect(await db().select().from(webhookEvent)).toHaveLength(0);
    expect(await db().select().from(subscription)).toHaveLength(0);
  });

  it("applies an event for one of our own products", async () => {
    const u = await makeUser({ plan: "trial" });
    const ours = {
      ...activeEvent(u.id),
      data: {
        ...activeEvent(u.id).data,
        product_id: env.DODOPAYMENT_MONTHLY_PRODUCT_ID,
      },
    };

    expect((await deliver(ours)).status).toBe(200);
    expect(scalar((await db().select().from(user).where(eq(user.id, u.id)))[0], "user").plan).toBe(
      "pro",
    );
  });

  /**
   * The filter fails open on a missing field on purpose. Dodo renaming or
   * dropping `product_id` would otherwise discard real upgrades silently,
   * which is far worse than the noise the filter removes. `metadata.userId`
   * is still the gate that decides whether anything is applied.
   */
  it("still applies an event that carries no product id at all", async () => {
    const u = await makeUser({ plan: "trial" });
    expect((await deliver(activeEvent(u.id))).status).toBe(200);
    expect(scalar((await db().select().from(user).where(eq(user.id, u.id)))[0], "user").plan).toBe(
      "pro",
    );
  });
});
