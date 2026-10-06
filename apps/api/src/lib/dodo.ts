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
    // Dodo's body says *which* field it rejected; the status alone does not,
    // and a 422 with no detail is an afternoon of guessing at the payload.
    // Safe to carry: this is our request being described back to us, and
    // logError scrubs key-shaped strings before anything is written.
    const detail = await response.text().catch(() => "");
    throw new Error(
      `dodo ${path} returned ${response.status}${detail ? `: ${detail.slice(0, 400)}` : ""}`,
    );
  }
  return response.json() as Promise<T>;
}

export function productIdFor(env: Env, plan: "pro" | "pro_annual"): string {
  const name =
    plan === "pro_annual" ? "DODOPAYMENT_YEARLY_PRODUCT_ID" : "DODOPAYMENT_MONTHLY_PRODUCT_ID";
  const productId = env[name];
  if (!productId) {
    // Deliberately a thrown error rather than a guess. A checkout opened
    // against a product id that does not exist is a 404 on Dodo's side that
    // reads to the user as a broken product.
    throw new Error(`${name} is not set`);
  }
  return productId;
}

/**
 * A billing country for the checkout.
 *
 * Dodo requires `billing.country` on every subscription — omitting it is a
 * 422 whose body says only "a field has an invalid value". Cloudflare already
 * knows where the request came from, which is a far better first guess than a
 * constant, and Dodo's hosted checkout lets the buyer correct it before
 * paying.
 *
 * `XX` and `T1` are Cloudflare's own "unknown" and "Tor" values, not
 * countries.
 */
export function billingCountry(header: string | null | undefined): string {
  const code = (header ?? "").toUpperCase();
  if (!/^[A-Z]{2}$/.test(code) || code === "XX" || code === "T1") return FALLBACK_COUNTRY;
  return code;
}

/** Only used when Cloudflare cannot say — including every local request. */
const FALLBACK_COUNTRY = "US";

export async function createCheckout(
  env: Env,
  options: {
    productId: string;
    email: string;
    name?: string | null;
    userId: string;
    returnUrl: string;
    country?: string | null;
  },
): Promise<{ url: string }> {
  const body = await call<{ payment_link?: string; url?: string }>(env, "/subscriptions", {
    method: "POST",
    body: JSON.stringify({
      product_id: options.productId,
      quantity: 1,
      payment_link: true,
      return_url: options.returnUrl,
      customer: {
        email: options.email,
        ...(options.name ? { name: options.name } : {}),
      },
      billing: { country: billingCountry(options.country) },
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
