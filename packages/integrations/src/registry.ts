import type { ConnectorCategory, ProviderId, ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "./types.ts";

// Revenue
import { stripe } from "./providers/stripe/index.ts";
import { dodopayments } from "./providers/dodopayments/index.ts";
import { lemonsqueezy } from "./providers/lemonsqueezy/index.ts";
import { polar } from "./providers/polar/index.ts";
import { paddle } from "./providers/paddle/index.ts";

// Product analytics
import { posthog } from "./providers/posthog/index.ts";
import { plausible } from "./providers/plausible/index.ts";
import { mixpanel } from "./providers/mixpanel/index.ts";
import { amplitude } from "./providers/amplitude/index.ts";
import { googleAnalytics } from "./providers/google-analytics/index.ts";

// Marketing and SEO
import { googleSearchConsole } from "./providers/google-search-console/index.ts";
import { ahrefs } from "./providers/ahrefs/index.ts";
import { googleAds } from "./providers/google-ads/index.ts";
import { metaAds } from "./providers/meta-ads/index.ts";

// CRM
import { hubspot } from "./providers/hubspot/index.ts";
import { intercom } from "./providers/intercom/index.ts";
import { github } from "./providers/github/index.ts";

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
  paddle,
  posthog,
  plausible,
  mixpanel,
  amplitude,
  "google-analytics": googleAnalytics,
  "google-search-console": googleSearchConsole,
  ahrefs,
  "google-ads": googleAds,
  "meta-ads": metaAds,
  hubspot,
  intercom,
  github,
};

/**
 * The ETag for `GET /v1/providers`, and the thing clients compare.
 *
 * Bump it in the same commit that changes any manifest. A stale value means an
 * app that has cached the old list never learns about the new provider, which
 * is a silent failure rather than a loud one.
 */
export const REGISTRY_VERSION = "2026-10-06.1";

export function getAdapter(id: string): ProviderAdapter {
  const adapter = (REGISTRY as Record<string, ProviderAdapter | undefined>)[id];
  if (!adapter) throw new Error(`unknown provider: ${id}`);
  return adapter;
}

export function manifests(): ProviderManifest[] {
  return Object.values(REGISTRY).map((adapter) => adapter.manifest);
}

/**
 * The catalogue, grouped the way the settings UI and the website show it.
 *
 * Within a category, connectors that actually work come first — a list whose
 * first three entries are all greyed out reads as a product that does not
 * work yet.
 */
export function catalogue(): { category: ConnectorCategory; connectors: ProviderManifest[] }[] {
  // A `Record` rather than an array, so adding a `ConnectorCategory` fails to
  // compile until it is given a position. As a plain list, a new category
  // type-checked fine and its connectors silently vanished from the
  // catalogue — which looks like a broken adapter, not a missing line here.
  const position: Record<ConnectorCategory, number> = {
    revenue: 0,
    analytics: 1,
    marketing: 2,
    crm: 3,
    developer: 4,
  };
  const order = (Object.keys(position) as ConnectorCategory[]).sort(
    (a, b) => position[a] - position[b],
  );
  const rank = (m: ProviderManifest) => (m.status === "stable" ? 0 : m.status === "beta" ? 1 : 2);

  return order.map((category) => ({
    category,
    connectors: manifests()
      .filter((m) => m.category === category)
      .sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name)),
  }));
}

/** Connectors a user can actually connect today. */
export function connectable(): ProviderManifest[] {
  return manifests().filter((m) => m.status !== "coming_soon");
}
