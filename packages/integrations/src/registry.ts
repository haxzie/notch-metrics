import { METRIC_KEYWORDS } from "@notch/schemas";
import type { ConnectorCategory, ProviderId, ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "./types.ts";

// Revenue
import { stripe } from "./providers/stripe/index.ts";
import { dodopayments } from "./providers/dodopayments/index.ts";
import { lemonsqueezy } from "./providers/lemonsqueezy/index.ts";
import { polar } from "./providers/polar/index.ts";
import { paddle } from "./providers/paddle/index.ts";
import { revenuecat } from "./providers/revenuecat/index.ts";

// Commerce
import { shopify } from "./providers/shopify/index.ts";

// Product analytics
import { posthog } from "./providers/posthog/index.ts";
import { plausible } from "./providers/plausible/index.ts";
import { mixpanel } from "./providers/mixpanel/index.ts";
import { amplitude } from "./providers/amplitude/index.ts";
import { googleAnalytics } from "./providers/google-analytics/index.ts";

// Marketing and SEO
import { googleSearchConsole } from "./providers/google-search-console/index.ts";
import { youtube } from "./providers/youtube/index.ts";

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
  revenuecat,
  shopify,
  posthog,
  plausible,
  mixpanel,
  amplitude,
  "google-analytics": googleAnalytics,
  "google-search-console": googleSearchConsole,
  youtube,
  hubspot,
  intercom,
  github,
};

/**
 * A fingerprint of every manifest, used as the ETag for the catalogue routes.
 *
 * Derived rather than hand-maintained. It used to be a date string with a
 * comment saying "bump it in the same commit that changes any manifest", and
 * that is exactly what went wrong: two connectors were promoted from
 * `coming_soon` to `stable` without touching it, so every client that
 * revalidated got a 304 and kept showing them as unavailable. Forever — a
 * cache that never expires because the server keeps agreeing with it.
 *
 * Content-derived means the only way to get a stale ETag is to change
 * nothing.
 */
export function fingerprintManifests(all: ProviderManifest[]): string {
  // FNV-1a. Not a security hash — this only has to change when the bytes do,
  // and it has to run on every catalogue request inside a Worker.
  const text = JSON.stringify(all);
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(36).padStart(7, "0");
}

export const REGISTRY_VERSION: string = fingerprintManifests(
  Object.values(REGISTRY).map((adapter) => adapter.manifest),
);

/**
 * Folds the shared metric synonyms into a manifest's own.
 *
 * Done here rather than in each manifest so "recurring revenue" is written
 * once and every provider offering `mrr` gets it. A manifest can still add
 * its own; both sets are searched.
 */
function withKeywords(manifest: ProviderManifest): ProviderManifest {
  return {
    ...manifest,
    keywords: manifest.keywords ?? [],
    metrics: manifest.metrics.map((metric) => ({
      ...metric,
      keywords: [...new Set([...(METRIC_KEYWORDS[metric.id] ?? []), ...(metric.keywords ?? [])])],
    })) as ProviderManifest["metrics"],
  };
}

/**
 * The registry with shared keywords folded in, built once.
 *
 * Enriching inside `manifests()` alone was a trap: `getAdapter(id).manifest`
 * returned the raw manifest, so the catalogue had keywords and every other
 * consumer silently did not. One table, so the two cannot disagree.
 */
const ENRICHED: Record<string, ProviderAdapter> = Object.fromEntries(
  Object.entries(REGISTRY).map(([id, adapter]) => [
    id,
    { ...adapter, manifest: withKeywords(adapter.manifest) } as ProviderAdapter,
  ]),
);

export function getAdapter(id: string): ProviderAdapter {
  const adapter = ENRICHED[id];
  if (!adapter) throw new Error(`unknown provider: ${id}`);
  return adapter;
}

export function manifests(): ProviderManifest[] {
  return Object.values(ENRICHED).map((adapter) => adapter.manifest);
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
