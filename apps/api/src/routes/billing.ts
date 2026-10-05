import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { CheckoutRequest } from "@notch/schemas";
import { subscription } from "@notch/db";
import { authenticate, sessionOnly, type AppContext } from "../middleware.ts";
import { billingState } from "../lib/entitlement.ts";
import { createCheckout, createPortalSession, productIdFor } from "../lib/dodo.ts";
import { loadUser } from "../lib/identity.ts";
import { logError } from "../lib/redact.ts";

export const billing = new Hono<AppContext>();

billing.use("*", authenticate);

billing.get("/", async (c) => c.json(await billingState(c.get("db"), c.get("identity").userId)));

billing.post("/checkout", sessionOnly, async (c) => {
  const body = CheckoutRequest.safeParse(await c.req.json().catch(() => ({})));
  const plan = body.success ? body.data.plan : "pro";

  const db = c.get("db");
  const userId = c.get("identity").userId;
  const user = await loadUser(db, userId);
  if (!user) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  const state = await billingState(db, userId);
  if (state.plan === "pro" && state.status === "active") {
    return c.json({ code: "ALREADY_PRO", message: "You are already subscribed." }, 409);
  }

  try {
    const result = await createCheckout(c.env, {
      productId: productIdFor(c.env, plan),
      email: user.email,
      userId,
      returnUrl: `${c.env.APP_URL}/app/settings/billing?checkout=done`,
    });
    return c.json(result);
  } catch (error) {
    logError("billing.checkout", error);
    // 503 rather than 500: this is almost always "the product id is not
    // configured yet", which is a deployment state, not a bug in the request.
    return c.json({ code: "BILLING_UNAVAILABLE", message: "Checkout is not available yet." }, 503);
  }
});

billing.post("/portal", sessionOnly, async (c) => {
  const db = c.get("db");
  const [row] = await db
    .select()
    .from(subscription)
    .where(eq(subscription.userId, c.get("identity").userId))
    .limit(1);

  if (!row?.dodoCustomerId) {
    return c.json({ code: "NO_CUSTOMER", message: "There is nothing to manage yet." }, 404);
  }

  try {
    return c.json(await createPortalSession(c.env, row.dodoCustomerId));
  } catch (error) {
    logError("billing.portal", error);
    return c.json({ code: "BILLING_UNAVAILABLE", message: "The portal is unavailable." }, 503);
  }
});
