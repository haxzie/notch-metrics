import type { ProviderId, ProviderManifest } from "@notch/schemas";
import { dodopayments } from "./providers/dodopayments/index.ts";
import { googleAnalytics } from "./providers/google-analytics/index.ts";
import { lemonsqueezy } from "./providers/lemonsqueezy/index.ts";
import { polar } from "./providers/polar/index.ts";
import { stripe } from "./providers/stripe/index.ts";
import type { ProviderAdapter } from "./types.ts";

/**
 * Every provider the API knows about.
 *
 * Adding one is four things and no more: a directory under `providers/`, a
 * line here, a manifest, and a test with recorded fixtures. No route changes,
 * and — because the Mac renders its settings UI from `GET /v1/providers` —
 * no app release.
 */
/**
 * Total over `ProviderId`, and typed that way on purpose.
 *
 * Adding an id to the enum without writing its adapter is then a compile
 * error here, rather than an "unknown provider" thrown at whichever user
 * connects it first. Adapters that are not finished declare
 * `status: "coming_soon"` and throw `unsupported`, which the settings UI
 * renders as greyed out.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const REGISTRY: Record<ProviderId, ProviderAdapter<any>> = {
  stripe,
  dodopayments,
  lemonsqueezy,
  polar,
  "google-analytics": googleAnalytics,
};

/**
 * The ETag for `GET /v1/providers`, and the thing clients compare.
 *
 * Bump it in the same commit that changes any manifest. A stale value means an
 * app that has cached the old list never learns about the new provider, which
 * is a silent failure rather than a loud one.
 */
export const REGISTRY_VERSION = "2026-10-05.2";

export function getAdapter(id: string): ProviderAdapter {
  const adapter = (REGISTRY as Record<string, ProviderAdapter | undefined>)[id];
  if (!adapter) throw new Error(`unknown provider: ${id}`);
  return adapter;
}

export function manifests(): ProviderManifest[] {
  return Object.values(REGISTRY).map((adapter) => adapter.manifest);
}
