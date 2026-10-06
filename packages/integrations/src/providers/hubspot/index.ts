import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "hubspot",
  name: "HubSpot",
  category: "crm",
  tagline: "Contacts, deals and pipeline from HubSpot.",
  docsUrl: "https://developers.hubspot.com/docs/api/oauth-quickstart-guide",
  iconPath: "/providers/hubspot.svg",
  accentColor: "#FF7A59",
  keywords: ["crm", "sales", "deals", "contacts", "pipeline"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your contacts", "Read your deals and pipelines"],
    requiresSelection: false,
  },
  fields: [],
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
    {
      id: "open_deals",
      label: "Open deals",
      shortLabel: "Open",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Deals currently in an open stage.",
    },
    {
      id: "won_deals",
      label: "Won deals",
      shortLabel: "Won",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Deals closed won in the window.",
    },
    {
      id: "pipeline_value",
      label: "Pipeline value",
      shortLabel: "Pipeline",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Total value of open deals.",
    },
  ],
  allowedHosts: ["api.hubapi.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  access_token: z.string().min(10).optional(),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.number().int().optional(),
});
export type HubspotCredentials = z.infer<typeof credentialSchema>;

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const hubspot: ProviderAdapter<HubspotCredentials> = {
  manifest,
  credentialSchema,
  userInputFields: [],
  async verify() {
    notImplemented("HubSpot");
  },
  async fetchMetric() {
    notImplemented("HubSpot");
  },
};
