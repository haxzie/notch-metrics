import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "ahrefs",
  name: "Ahrefs",
  category: "marketing",
  tagline: "Backlinks, domain rating and organic keywords from Ahrefs.",
  docsUrl: "https://ahrefs.com/api/documentation",
  iconPath: "/providers/ahrefs.svg",
  accentColor: "#FF8C00",
  keywords: ["seo", "backlinks", "keywords", "domain rating"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API token",
      type: "secret",
      required: true,
      help: "Account Settings \u2192 API keys. Ahrefs bills per API row.",
    },
    {
      key: "target",
      label: "Domain",
      type: "string",
      required: true,
      help: "The domain to report on, e.g. example.com.",
    },
  ],
  metrics: [
    {
      id: "backlinks",
      label: "Backlinks",
      shortLabel: "Links",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "External links pointing at the domain.",
    },
    {
      id: "domain_rating",
      label: "Domain rating",
      shortLabel: "DR",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Ahrefs' 0-100 strength score for the domain.",
    },
    {
      id: "organic_keywords",
      label: "Organic keywords",
      shortLabel: "Keywords",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Keywords the domain ranks for organically.",
    },
  ],
  allowedHosts: ["api.ahrefs.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  target: z.string().min(1),
});
export type AhrefsCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const ahrefs: ProviderAdapter<AhrefsCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Ahrefs");
  },
  async fetchMetric() {
    notImplemented("Ahrefs");
  },
};
