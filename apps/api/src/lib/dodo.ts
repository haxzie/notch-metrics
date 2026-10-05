import { required, type Env } from "../env.ts";

/**
 * Dodo Payments over plain `fetch`.
 *
 * No SDK: this is three endpoints, the HTTP shape is the contract either way,
 * and a Node-shaped SDK in a Worker bundle costs more than it saves.
 */
function baseUrl(env: Env): string {
  // The mode is explicit configuration rather than inferred from the key. A
  // live key against the test host answers 401, which reads as a bad key and
  // costs an hour before anybody suspects the host.
  return env.DODOPAYMENT_MODE === "test"
    ? "https://test.dodopayments.com"
    : "https://live.dodopayments.com";
}

async function call<T>(env: Env, path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${baseUrl(env)}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${required(env, "DODOPAYMENT_API_KEY")}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  if (!response.ok) {
    throw new Error(`dodo ${path} returned ${response.status}`);
  }
  return response.json() as Promise<T>;
}

export function productIdFor(env: Env, plan: "pro" | "pro_annual"): string {
  const productId =
    plan === "pro_annual" ? env.DODOPAYMENT_PRO_ANNUAL_PRODUCT_ID : env.DODOPAYMENT_PRO_PRODUCT_ID;
  if (!productId) {
    // Deliberately a thrown error rather than a guess. A checkout opened
    // against a product id that does not exist is a 404 on Dodo's side that
    // reads to the user as a broken product.
    throw new Error(
      `DODOPAYMENT_${plan === "pro_annual" ? "PRO_ANNUAL" : "PRO"}_PRODUCT_ID is not set`,
    );
  }
  return productId;
}

export async function createCheckout(
  env: Env,
  options: { productId: string; email: string; userId: string; returnUrl: string },
): Promise<{ url: string }> {
  const body = await call<{ payment_link?: string; url?: string }>(env, "/subscriptions", {
    method: "POST",
    body: JSON.stringify({
      product_id: options.productId,
      quantity: 1,
      payment_link: true,
      return_url: options.returnUrl,
      customer: { email: options.email },
      // The only link back from a Dodo event to one of our users. Without it
      // the webhook has an email address and a guess.
      metadata: { userId: options.userId },
    }),
  });

  const url = body.payment_link ?? body.url;
  if (!url) throw new Error("dodo did not return a payment link");
  return { url };
}

export async function createPortalSession(env: Env, customerId: string): Promise<{ url: string }> {
  const body = await call<{ link?: string; url?: string }>(
    env,
    `/customers/${customerId}/customer-portal/session`,
    { method: "POST" },
  );
  const url = body.link ?? body.url;
  if (!url) throw new Error("dodo did not return a portal link");
  return { url };
}
