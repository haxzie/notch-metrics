import { createHttp, getAdapter, ProviderError } from "@notch/integrations";
import type { AdapterContext } from "@notch/integrations";
import type { MetricErrorCode } from "@notch/schemas";

/**
 * Builds the context an adapter runs in.
 *
 * The allowlist comes from the adapter's own manifest rather than from a
 * caller-supplied list, so a route cannot widen it by accident.
 */
export function adapterContext(options: {
  provider: string;
  timeZone: string;
  preferredCurrency: string;
  signal: AbortSignal;
  /**
   * Told about every provider request this context makes. The caller keeps
   * them so a failure can be recorded with the status that caused it rather
   * than only our own name for it — "404 on api.github.com" against
   * "auth_failed" is the whole difference when reading back why a connection
   * broke.
   */
  onCall?: (call: { host: string; method: string; status: number | null; ms: number }) => void;
}): AdapterContext {
  const adapter = getAdapter(options.provider);
  return {
    http: createHttp({
      allowedHosts: adapter.manifest.allowedHosts,
      signal: options.signal,
      onCall: options.onCall,
    }),
    now: () => new Date(),
    timeZone: options.timeZone,
    preferredCurrency: options.preferredCurrency,
    signal: options.signal,
    log: (message, fields) => console.log(`[${options.provider}] ${message}`, fields ?? ""),
  };
}

export function toMetricError(error: unknown): {
  code: MetricErrorCode;
  message: string;
  retryAfterSeconds: number | null;
} {
  if (error instanceof ProviderError) {
    return {
      code: error.code === "bad_response" ? "provider_down" : error.code,
      message: error.message,
      retryAfterSeconds: error.retryAfterSeconds ?? null,
    };
  }
  // Never surface a raw message: it can quote the failing request, which can
  // quote the Authorization header.
  return {
    code: "provider_down",
    message: "That provider could not be reached.",
    retryAfterSeconds: null,
  };
}
