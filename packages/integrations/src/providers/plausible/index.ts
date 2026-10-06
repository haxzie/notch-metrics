import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "plausible",
  name: "Plausible",
  category: "analytics",
  tagline: "Privacy-friendly traffic numbers from Plausible.",
  docsUrl: "https://plausible.io/docs/stats-api",
  iconPath: "/providers/plausible.svg",
  accentColor: "#5850EC",
  keywords: ["web analytics", "privacy", "traffic", "visitors"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Settings \u2192 API keys.",
    },
    {
      key: "site_id",
      label: "Site",
      type: "string",
      required: true,
      help: "The domain as it appears in Plausible, e.g. example.com.",
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
      methodology: "Distinct visitors in the window.",
    },
    {
      id: "pageviews",
      label: "Pageviews",
      shortLabel: "Views",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Total pages viewed in the window.",
    },
    {
      id: "bounce_rate",
      label: "Bounce rate",
      shortLabel: "Bounce",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Share of sessions with a single interaction.",
    },
    {
      id: "sessions",
      label: "Sessions",
      shortLabel: "Sessions",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Sessions started in the window.",
    },
  ],
  allowedHosts: ["plausible.io"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  site_id: z.string().min(1),
});
export type PlausibleCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const plausible: ProviderAdapter<PlausibleCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Plausible");
  },
  async fetchMetric() {
    notImplemented("Plausible");
  },
};
