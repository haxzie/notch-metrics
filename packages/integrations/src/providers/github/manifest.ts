import type { ProviderManifest } from "@notch/schemas";

/**
 * Everything about the connector that is not a metric.
 *
 * `metrics` is absent on purpose — `provider()` derives it from the metric
 * definitions, so a descriptor and the code that answers it cannot drift,
 * and a metric cannot be added to one without the other.
 */
export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "Stars, forks and open work, per repository.",
  docsUrl: "https://docs.github.com/en/rest/metrics",
  dashboardUrl: "https://github.com",
  iconPath: "/connectors/github.svg",
  // The brand black. The catalogue renders the mark on a light tile rather
  // than white on this, which is how GitHub itself shows the logo.
  accentColor: "#181717",
  keywords: ["repo", "repository", "open source", "code", "issues"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: [
      "Read your repositories, public and private",
      "GitHub grants this as full repository access. Notch Metrics only reads.",
      "Read your name and avatar",
    ],
    // Authorising is the whole connection now. The repository moved onto the
    // widget, so one GitHub account serves a tile per repository instead of
    // needing a connection each — which also means the stars of a repo you
    // do not own no longer costs a second connection.
    requiresSelection: false,
  },
  fields: [],
  allowedHosts: ["api.github.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
