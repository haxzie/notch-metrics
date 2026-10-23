import type { ProviderManifest } from "@notch/schemas";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "plausible",
  name: "Plausible",
  category: "analytics",
  tagline: "Privacy-friendly traffic numbers from Plausible.",
  docsUrl: "https://plausible.io/docs/stats-api",
  dashboardUrl: "https://plausible.io",
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
  // Cloud only. Self-hosted Plausible speaks the same API on the operator's
  // own domain, which an allowlist fixed at build time cannot admit.
  allowedHosts: ["plausible.io"],
  // Beta until the numbers have been read back against a live site's own
  // dashboard. Every call here is shaped from Plausible's documentation
  // rather than from a recorded response.
  status: "beta",
  minAppVersion: "0.1.0",
};
