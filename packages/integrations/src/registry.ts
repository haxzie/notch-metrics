import type { ProviderId, ProviderManifest } from "@notch/schemas";
import { dodopayments } from "./providers/dodopayments/index.ts";
import { lemonsqueezy } from "./providers/lemonsqueezy/index.ts";
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
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const REGISTRY: Record<ProviderId, ProviderAdapter<any>> = {
  stripe,
  dodopayments,
  lemonsqueezy,
  // `polar` is declared in the ProviderId enum but has no adapter yet. Listing
  // it here with a stub would make it appear connectable; leaving it out makes
  // `getAdapter` throw, which is the honest outcome.
} as never;

/**
 * The ETag for `GET /v1/providers`, and the thing clients compare.
 *
 * Bump it in the same commit that changes any manifest. A stale value means an
 * app that has cached the old list never learns about the new provider, which
 * is a silent failure rather than a loud one.
 */
export const REGISTRY_VERSION = "2026-10-05.1";

export function getAdapter(id: string): ProviderAdapter {
  const adapter = (REGISTRY as Record<string, ProviderAdapter | undefined>)[id];
  if (!adapter) throw new Error(`unknown provider: ${id}`);
  return adapter;
}

export function manifests(): ProviderManifest[] {
  return Object.values(REGISTRY).map((adapter) => adapter.manifest);
}
