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

/** Turns a provider's HTTP status into our taxonomy, honouring Retry-After. */
export function errorForStatus(host: string, response: HttpResponse): ProviderError {
  if (response.status === 401 || response.status === 403) {
    return new ProviderError("auth_failed", `${host} rejected the credentials`);
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
