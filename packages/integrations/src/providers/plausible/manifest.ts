import type { ProviderManifest } from "@notch/schemas";

/**
 * Days are the *site's* reporting timezone, not the user's.
 *
 * Repeated in every methodology rather than said once, because it is the
 * answer to "why is this 40 and the dashboard says 41" and nobody reads the
 * tooltip of the metric next door.
 */
const ZONE_NOTE =
  "Buckets are your Plausible site's reporting timezone, so the figures match its own dashboard.";

export const manifest: ProviderManifest = {
  id: "plausible",
  name: "Plausible",
  category: "analytics",
  tagline: "Privacy-friendly traffic numbers from Plausible.",
  docsUrl: "https://plausible.io/docs/stats-api",
  iconPath: "/connectors/plausible.svg",
  accentColor: "#5850EC",
  keywords: ["web analytics", "privacy", "traffic", "visitors"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      // The plan requirement is here rather than in the docs link because a
      // Growth-plan key is accepted by the form, rejected by Plausible, and
      // the rejection reads as a mistyped key.
      help: "Account settings → API Keys → new Stats API key. Needs a Business plan.",
    },
    {
      key: "site_id",
      label: "Site",
      type: "string",
      required: true,
      placeholder: "example.com",
      // A key is scoped to one Plausible team, and a site owned by another
      // team answers 404 however correct the domain is.
      help: "The domain as it appears in Plausible, owned by the key's team.",
    },
  ],
  metrics: [
    {
      id: "visitors",
      label: "Unique visitors",
      shortLabel: "Visitors",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Distinct visitors in the window. The headline counts each visitor once across the whole window, so the bars do not add up to it. ${ZONE_NOTE}`,
    },
    {
      id: "pageviews",
      label: "Pageviews",
      shortLabel: "Views",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Total pages viewed in the window — repeat views by one visitor all count. ${ZONE_NOTE}`,
    },
    {
      id: "bounce_rate",
      label: "Bounce rate",
      shortLabel: "Bounce",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Share of sessions that left after one interaction. Plausible computes each bar over its own bucket, so a week is weighted by its sessions rather than being the mean of seven daily rates. ${ZONE_NOTE}`,
    },
    {
      id: "sessions",
      label: "Sessions",
      shortLabel: "Sessions",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Visits started in the window — Plausible's "visits". A session that spans midnight is counted in the bucket it started in. ${ZONE_NOTE}`,
    },
  ],
  // Cloud only. Self-hosted Plausible speaks the same API on the operator's
  // own domain, which an allowlist fixed at build time cannot admit.
  allowedHosts: ["plausible.io"],
  // Beta until the numbers have been read back against a live site's own
  // dashboard. Every call here is shaped from Plausible's documentation
  // rather than from a recorded response.
  status: "beta",
  minAppVersion: "0.1.0",
};
