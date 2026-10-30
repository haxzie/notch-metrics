import { redactCredentials } from "./redact.ts";
import type { AdapterContext, HttpResponse } from "./types.ts";
import { ProviderError } from "./types.ts";

const DEFAULT_TIMEOUT_MS = 8_000;
const MAX_BYTES = 4 * 1024 * 1024;
const MAX_REDIRECTS = 3;

/** `api.stripe.com` matches `api.stripe.com`; `*.example.com` matches one label. */
export function hostAllowed(host: string, allowed: readonly string[]): boolean {
  const h = host.toLowerCase();
  return allowed.some((pattern) => {
    const p = pattern.toLowerCase();
    if (p.startsWith("*.")) {
      const suffix = p.slice(1); // ".example.com"
      return h.endsWith(suffix) && h.slice(0, -suffix.length).split(".").length === 1;
    }
    return h === p;
  });
}

export function createHttp(options: {
  allowedHosts: readonly string[];
  signal: AbortSignal;
  timeoutMs?: number;
  onCall?: (call: { host: string; method: string; status: number | null; ms: number }) => void;
}): AdapterContext["http"] {
  const { allowedHosts, signal, timeoutMs = DEFAULT_TIMEOUT_MS, onCall } = options;

  return async function http(url: string, init: RequestInit = {}): Promise<HttpResponse> {
    let target = new URL(url);
    const started = Date.now();
    const method = (init.method ?? "GET").toUpperCase();

    for (let hop = 0; ; hop++) {
      if (target.protocol !== "https:") {
        throw new ProviderError("unsupported", `refusing a non-https request to ${target.host}`);
      }
      if (!hostAllowed(target.hostname, allowedHosts)) {
        // The allowlist is re-checked on every hop, not just the first. A
        // provider that 302s off-allowlist would otherwise receive the
        // Authorization header this request carries.
        throw new ProviderError("unsupported", `host ${target.hostname} is not allowed`);
      }

      const timeout = AbortSignal.timeout(timeoutMs);
      const combined = AbortSignal.any([signal, timeout]);

      let response: Response;
      try {
        response = await fetch(target, { ...init, redirect: "manual", signal: combined });
      } catch (cause) {
        if (timeout.aborted) {
          throw new ProviderError(
            "provider_down",
            `${target.hostname} timed out after ${timeoutMs}ms`,
          );
        }
        throw new ProviderError("provider_down", `could not reach ${target.hostname}`, undefined);
      }

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (!location) throw new ProviderError("bad_response", "redirect with no Location");
        if (hop >= MAX_REDIRECTS) throw new ProviderError("bad_response", "too many redirects");
        target = new URL(location, target);
        continue;
      }

      onCall?.({
        host: target.hostname,
        method,
        status: response.status,
        ms: Date.now() - started,
      });

      const length = Number(response.headers.get("content-length") ?? "0");
      if (length > MAX_BYTES) {
        throw new ProviderError("bad_response", `${target.hostname} returned more than 4 MB`);
      }

      return {
        ok: response.ok,
        status: response.status,
        headers: response.headers,
        json: <T>() => response.json() as Promise<T>,
        text: () => response.text(),
      };
    }
  };
}

/**
 * `errorForStatus`, with the provider's own explanation attached.
 *
 * A 4xx that is not 401, 403 or 429 is the provider saying the *request* was
 * wrong, and it almost always says which part in the body. Throwing that away
 * leaves "api.anthropic.com returned 400" on screen, and the cause then has
 * to be guessed from outside the system — which is how a bad query parameter
 * survives a release.
 *
 * Only for 4xx, and only once. A 5xx body is usually an HTML error page, and
 * a 429 is fully described by its status plus the Retry-After we already read.
 *
 * 401 and 403 *do* get the provider's words, which they used not to. The
 * reasoning for withholding them was that "rejected the credentials" already
 * says everything — and that is true for a mistyped key and false for every
 * scoped-token product shipped since. A Stripe restricted key missing one
 * permission returns 403 with the scope name and the dashboard page that
 * grants it; we replaced all of that with the number, and a user who reads
 * "rejected the credentials" makes a new key rather than ticking one box.
 * That cost us a signup we watched happen.
 */
export async function errorForResponse(
  host: string,
  response: HttpResponse,
): Promise<ProviderError> {
  const base = errorForStatus(host, response);
  if (response.status >= 500 || response.status === 429) return base;

  const detail = await providerMessage(response);
  return detail
    ? new ProviderError(base.code, `${base.message}: ${detail}`, base.retryAfterSeconds)
    : base;
}

/**
 * The human-readable half of a provider's error body.
 *
 * Every shape here is one a connector in this package actually receives.
 * `{ error: { message } }` is Stripe, OpenAI and Anthropic; a bare
 * `{ message }` is most of the rest; `{ errors: [...] }` is Shopify and
 * GitHub; `{ detail }` is anything built on FastAPI, which includes Polar.
 * Anything unrecognised is dropped rather than pasted in raw: an HTML page or
 * a stack trace in a notch tile is worse than the bare status it replaces.
 *
 * Two passes over the text before it is returned, and neither is cosmetic:
 *
 * `redactCredentials`, because this string is headed for a user's screen and
 * a provider is free to quote the key we just sent it. Stripe quotes a
 * truncated one; nothing promises the next provider will truncate.
 *
 * Sentences containing a URL are dropped whole, rather than having the URL
 * cut out of them. Providers append their own console deep links, which run
 * to a couple of hundred characters of account id and query string and would
 * eat the entire budget below. Removing just the link leaves "You can edit
 * permissions at ." behind, so the sentence goes with it: where to click is
 * our job to say, and `docsUrl` plus `setupSteps` is where we say it.
 */
async function providerMessage(response: HttpResponse): Promise<string | null> {
  try {
    const body = (await response.json()) as {
      error?: { message?: unknown } | string;
      errors?: unknown;
      message?: unknown;
      detail?: unknown;
      error_description?: unknown;
    };

    const candidates: unknown[] = [
      typeof body?.error === "object" && body.error !== null
        ? (body.error as { message?: unknown }).message
        : body?.error,
      body?.message,
      body?.detail,
      body?.error_description,
      Array.isArray(body?.errors)
        ? body.errors
            .map((e) => (typeof e === "string" ? e : (e as { message?: unknown })?.message))
            .filter((e): e is string => typeof e === "string" && e.trim() !== "")
            .join(" ")
        : typeof body?.errors === "string"
          ? body.errors
          : undefined,
    ];

    const raw = candidates.find((c): c is string => typeof c === "string" && c.trim() !== "");
    if (raw === undefined) return null;

    const cleaned = redactCredentials(raw)
      .split(/(?<=[.!?])\s+/)
      .filter((sentence) => !/https?:\/\//.test(sentence))
      .join(" ")
      .replace(/\s+/g, " ")
      .trim();
    if (cleaned === "") return null;

    // Bounded, but generously. The old 200 cut Stripe's permission message off
    // mid-clause, before the part naming the permission.
    return cleaned.length > 400 ? `${cleaned.slice(0, 397)}...` : cleaned;
  } catch {
    return null;
  }
}

/** Turns a provider's HTTP status into our taxonomy, honouring Retry-After. */
export function errorForStatus(host: string, response: HttpResponse): ProviderError {
  if (response.status === 401 || response.status === 403) {
    // The status is part of the message on purpose. 401 and 403 are both
    // "rejected" to the user, but a 403 from a host that normally says 401
    // is how a WAF in front of the provider shows up, and that is a
    // different afternoon from a mistyped key.
    return new ProviderError(
      "auth_failed",
      `${host} rejected the credentials (${response.status})`,
    );
  }
  if (response.status === 429) {
    const retry = Number(response.headers.get("retry-after") ?? "60");
    return new ProviderError(
      "rate_limited",
      `${host} asked us to wait`,
      Number.isFinite(retry) ? retry : 60,
    );
  }
  if (response.status >= 500) {
    return new ProviderError("provider_down", `${host} returned ${response.status}`);
  }
  return new ProviderError("bad_response", `${host} returned ${response.status}`);
}
