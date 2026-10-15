import { catalogue, connectable, getAdapter } from "@notch/integrations";
import { CONNECTOR_CATEGORY_LABELS, RANGE_DURATION_MS } from "@notch/schemas";
import type {
  ConnectorCategory,
  MetricDescriptor,
  MetricId,
  ProviderManifest,
} from "@notch/schemas";

/**
 * `/sources` and everything under it, derived from the provider manifests.
 *
 * Nothing here is a list of pages. The manifests in `packages/integrations`
 * are the list: a descriptor added to one becomes a live page, a sitemap
 * entry and an `llms.txt` line with no edit in this app. That is deliberate
 * and it is the only version that survives, because a hand-kept copy of the
 * catalogue is exactly what `src/lib/connectors.ts` used to be, and it
 * drifted within one release.
 *
 * Safe to call from a statically rendered route: `@notch/integrations` has no
 * `node:` or `cloudflare:` import, reads no environment at module load, and
 * its adapters reach the network only through an injected `ctx.http` that
 * nothing here ever calls. It is a pure data read.
 *
 * Three traps in the manifests that this module exists to absorb:
 *
 * 1. **The same metric id has a different label per provider.** `revenue` is
 *    "Revenue" on Stripe, "Total revenue" on Dodo Payments, "Sales" on
 *    Shopify and "Estimated revenue" on YouTube. Titles come from the
 *    descriptor, never from the id.
 * 2. **`arr` and `conversion_rate` are in `MetricId` with no descriptor
 *    anywhere.** Driving off `manifest.metrics` rather than the enum skips
 *    them without a deny-list that would need maintaining.
 * 3. **`recent_payments` is a list, not a number.** It needs its own page
 *    body, so `isList` is surfaced rather than inferred at each call site.
 */

export type SourcePage = {
  manifest: ProviderManifest;
  path: string;
};

export type MetricPage = {
  manifest: ProviderManifest;
  metric: MetricDescriptor;
  path: string;
  /** A feed of rows rather than a single figure. Different page body. */
  isList: boolean;
};

/**
 * Metric ids are snake_case and the URL form is hyphenated.
 *
 * Both directions live here and nowhere else. The server validates metric
 * *params* against `^[a-z][a-z0-9_]{0,31}$`, but a metric id never travels in
 * a URL anywhere except these pages, so the spelling is ours alone to pick.
 */
export function metricSlug(id: string): string {
  return id.replace(/_/g, "-");
}

export function metricIdFromSlug(slug: string): string {
  return slug.replace(/-/g, "_");
}

/** Providers with a page. `coming_soon` ones get none. */
export function sourcePages(): SourcePage[] {
  return connectable().map((manifest) => ({
    manifest,
    path: `/sources/${manifest.id}`,
  }));
}

/**
 * `coming_soon` providers are excluded, and that is the whole reason this
 * goes through `connectable()`.
 *
 * Their adapters throw `notImplemented` from both `verify` and `fetchMetric`,
 * so a page for one would rank for a number the product cannot return and
 * send the reader to a connect flow that fails. A provider promoted to `beta`
 * appears here on the next build with no edit.
 */
export function metricPages(): MetricPage[] {
  return sourcePages().flatMap(({ manifest, path }) =>
    manifest.metrics.map((metric) => ({
      manifest,
      metric,
      path: `${path}/${metricSlug(metric.id)}`,
      isList: metric.id === "recent_payments",
    })),
  );
}

export function sourceBySlug(slug: string): ProviderManifest | undefined {
  return connectable().find((manifest) => manifest.id === slug);
}

export function metricBySlug(
  providerSlug: string,
  metricSlugValue: string,
): MetricPage | undefined {
  const manifest = sourceBySlug(providerSlug);
  if (!manifest) return undefined;

  const id = metricIdFromSlug(metricSlugValue);
  const metric = manifest.metrics.find((candidate) => candidate.id === id);
  if (!metric) return undefined;

  return {
    manifest,
    metric,
    path: `/sources/${manifest.id}/${metricSlugValue}`,
    isList: metric.id === "recent_payments",
  };
}

/** The index, in the catalogue's own order, with `coming_soon` dropped. */
export function sourceGroups(): {
  category: ConnectorCategory;
  label: string;
  manifests: ProviderManifest[];
}[] {
  return catalogue()
    .map((group) => ({
      category: group.category,
      label: CONNECTOR_CATEGORY_LABELS[group.category],
      manifests: group.connectors.filter((manifest) => manifest.status !== "coming_soon"),
    }))
    .filter((group) => group.manifests.length > 0);
}

/**
 * Every other connector reporting the same number.
 *
 * This is the block that stops seventy-seven metric pages reading as one page
 * with the nouns swapped: it varies by metric rather than by provider, and
 * each row carries that provider's own label and its own methodology
 * sentence, which genuinely differ. Stripe's MRR normalises annual plans by
 * dividing by twelve; RevenueCat's comes off their charts endpoint. Those are
 * not the same number and the table says so.
 */
export function providersReporting(
  id: MetricId,
  exclude?: string,
): { manifest: ProviderManifest; metric: MetricDescriptor; path: string }[] {
  return connectable()
    .filter((manifest) => manifest.id !== exclude)
    .flatMap((manifest) => {
      const metric = manifest.metrics.find((candidate) => candidate.id === id);
      return metric
        ? [{ manifest, metric, path: `/sources/${manifest.id}/${metricSlug(id)}` }]
        : [];
    });
}

/** `getAdapter` is the enriched table, so keywords are already folded in. */
export function metricKeywords(providerId: string, id: MetricId): string[] {
  const metric = getAdapter(providerId).manifest.metrics.find((candidate) => candidate.id === id);
  return metric?.keywords ?? [];
}

/**
 * A manifest string with its backticks removed.
 *
 * For places where there is no markup to render them into: a meta
 * description, an FAQ answer that a search engine will read aloud. Backticks
 * in a SERP snippet are litter.
 */
export function plain(text: string): string {
  return text.replace(/`/g, "");
}

const UNIT_COPY: Record<MetricDescriptor["unit"], string> = {
  currency:
    "An amount of money, held as integer minor units with an ISO 4217 code, so nothing is ever a rounded float.",
  count: "A whole number.",
  ratio: "A fraction, rendered as a percentage.",
  duration: "A length of time, held in seconds and shown in whichever unit reads best.",
  bytes: "A size in bytes.",
};

export function unitDescription(unit: MetricDescriptor["unit"]): string {
  return UNIT_COPY[unit];
}

const GRANULARITY_LABELS: Record<string, string> = {
  hour: "hourly",
  day: "daily",
  week: "weekly",
  month: "monthly",
};

export function granularityPhrase(metric: MetricDescriptor): string {
  const labels = metric.granularities.map((g) => GRANULARITY_LABELS[g] ?? g);
  if (labels.length === 1) return labels[0]!;
  return `${labels.slice(0, -1).join(", ")} and ${labels[labels.length - 1]}`;
}

/** The windows a widget can ask for, shared across every provider. */
export const WINDOWS = Object.keys(RANGE_DURATION_MS) as (keyof typeof RANGE_DURATION_MS)[];

export function statusNote(status: ProviderManifest["status"]): string | null {
  if (status === "beta") {
    return "This connector is in beta. It connects and returns numbers; the edges are still being worked on.";
  }
  return null;
}

export function authPhrase(manifest: ProviderManifest): string {
  return manifest.authMode === "oauth2"
    ? "Sign in through the provider. No key is typed in anywhere."
    : "Paste a key on the web, once.";
}

/**
 * The FAQ a `/sources/<provider>` page gets when no sidecar names one.
 *
 * Built from manifest facts so the answers are true per provider rather than
 * one paragraph with the name swapped. Each answer repeats its subject,
 * because these get lifted and shown with nothing around them.
 */
export function generatedSourceFaq(
  manifest: ProviderManifest,
): { question: string; answer: string }[] {
  const names = manifest.metrics.map((metric) => metric.label.toLowerCase());
  const list =
    names.length > 1
      ? `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
      : (names[0] ?? "");

  const faq = [
    {
      question: `What ${manifest.name} numbers can Notch Metrics show?`,
      answer: `Notch Metrics reports ${names.length} ${manifest.name} ${
        names.length === 1 ? "number" : "numbers"
      }: ${list}. Each one is a widget you place in the MacBook notch, sized from a single square up to the full width.`,
    },
    {
      question: `How do you connect ${manifest.name} to Notch Metrics?`,
      answer:
        manifest.authMode === "oauth2"
          ? `Sign in to notchmetrics.com, choose ${manifest.name} and approve the prompt. Nothing is typed in, and every Mac on your account picks the connection up.`
          : `Sign in to notchmetrics.com, choose ${manifest.name} and paste your key. ${
              plain(manifest.fields[0]?.help ?? "") ||
              "The key is encrypted the moment it arrives and never reaches your Mac."
            }`,
    },
    {
      question: `Does the Notch Metrics Mac app hold my ${manifest.name} key?`,
      answer: `No. Our server calls ${manifest.name} and hands your Mac a normalised number. Your ${manifest.name} credential is encrypted with its own key, bound to your account and the provider, so a row copied anywhere else does not decrypt.`,
    },
    {
      question: `What does ${manifest.name} in the notch cost?`,
      answer: `Every connector is included, with no per-integration charge. Notch Metrics is $9 a month or $49 a year, after a seven-day trial that needs no card. ${manifest.name} counts as one of the connectors on every plan.`,
    },
  ];

  const note = statusNote(manifest.status);
  if (note) {
    faq.push({
      question: `Is the ${manifest.name} connector ready to use?`,
      answer: `${manifest.name} is in beta. It connects, and it returns ${list}. Beta here means the edges are still being worked on, not that the numbers are unavailable.`,
    });
  }

  return faq;
}

/** The same, for one metric. */
export function generatedMetricFaq(
  manifest: ProviderManifest,
  metric: MetricDescriptor,
): { question: string; answer: string }[] {
  const others = providersReporting(metric.id, manifest.id);
  const full = `${manifest.name} ${metric.label.toLowerCase()}`;

  const faq = [
    {
      question: `How is ${full} calculated?`,
      answer: `${plain(metric.methodology)} Notch Metrics reports that number, unchanged, in the MacBook notch.`,
    },
    {
      question: `Can I see ${full} over time?`,
      answer: metric.supportsSeries
        ? `Yes. ${manifest.name} ${metric.label.toLowerCase()} is bucketed ${granularityPhrase(metric)}, so the widget carries a sparkline alongside the headline figure${metric.supportsCompare ? ", and a comparison against the previous window" : ""}.`
        : `${manifest.name} ${metric.label.toLowerCase()} is a snapshot of right now, so the widget shows the figure without a sparkline. ${metric.supportsCompare ? "It still compares against the previous window." : "The windows it accepts are 24 hours, 7, 30 and 90 days, and 12 months."}`,
    },
    {
      question: `What unit is ${full} in?`,
      answer: `${unitDescription(metric.unit)} ${
        metric.unit === "currency"
          ? `Amounts are reported in your ${manifest.name} account's own currency.`
          : ""
      }`.trim(),
    },
  ];

  if (others.length > 0) {
    const names = others.map((other) => other.manifest.name);
    faq.push({
      question: `Which other sources report ${metric.label.toLowerCase()}?`,
      answer: `Besides ${manifest.name}, Notch Metrics reports ${metric.label.toLowerCase()} from ${
        names.length > 1
          ? `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
          : names[0]
      }. Each provider defines the number its own way, so the widgets stay separate rather than being added together.`,
    });
  }

  faq.push({
    question: `What does it cost to put ${full} in the notch?`,
    answer: `$9 a month, or $49 a year, with every connector included and no per-integration charge. The seven-day trial needs no card, so you can see your own ${metric.label.toLowerCase()} before deciding.`,
  });

  return faq;
}
