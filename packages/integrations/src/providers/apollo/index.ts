import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "apollo",
  name: "Apollo",
  category: "crm",
  tagline: "Contact and sequence numbers from Apollo.",
  docsUrl: "https://docs.apollo.io/docs/create-api-key",
  iconPath: "/providers/apollo.svg",
  accentColor: "#3B47D2",
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Settings \u2192 Integrations \u2192 API.",
    },
  ],
  metrics: [
    {
      id: "contacts",
      label: "Contacts",
      shortLabel: "Contacts",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Total contacts in the CRM.",
    },
    {
      id: "new_contacts",
      label: "New contacts",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Contacts created in the window.",
    },
  ],
  allowedHosts: ["api.apollo.io"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
});
export type ApolloCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const apollo: ProviderAdapter<ApolloCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Apollo");
  },
  async fetchMetric() {
    notImplemented("Apollo");
  },
};
