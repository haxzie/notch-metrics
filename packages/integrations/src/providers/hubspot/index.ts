import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import { metricsFor, provider } from "../../metric.ts";
import { notImplemented } from "../../types.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "hubspot",
  name: "HubSpot",
  category: "crm",
  tagline: "Contacts, deals and pipeline from HubSpot.",
  docsUrl: "https://developers.hubspot.com/docs/api/oauth-quickstart-guide",
  dashboardUrl: "https://app.hubspot.com",
  iconPath: "/connectors/hubspot.svg",
  accentColor: "#FF7A59",
  keywords: ["crm", "sales", "deals", "contacts", "pipeline"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your contacts", "Read your deals and pipelines"],
    requiresSelection: false,
  },
  fields: [],
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

const { scalar, series } = metricsFor<HubspotCredentials>();

const contacts = scalar({
  id: "contacts",
  label: "Contacts",
  shortLabel: "Contacts",
  unit: "count",
  freshnessSeconds: 300,
  methodology: "Total contacts in the CRM.",

  async fetch() {
    notImplemented("HubSpot");
  },
});

const newContacts = series({
  id: "new_contacts",
  label: "New contacts",
  shortLabel: "New",
  unit: "count",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 300,
  methodology: "Contacts created in the window.",

  async fetch() {
    notImplemented("HubSpot");
  },
});

const openDeals = scalar({
  id: "open_deals",
  label: "Open deals",
  shortLabel: "Open",
  unit: "count",
  freshnessSeconds: 300,
  methodology: "Deals currently in an open stage.",

  async fetch() {
    notImplemented("HubSpot");
  },
});

const wonDeals = series({
  id: "won_deals",
  label: "Won deals",
  shortLabel: "Won",
  unit: "count",
  compare: true,
  granularities: ["day", "week", "month"],
  freshnessSeconds: 300,
  methodology: "Deals closed won in the window.",

  async fetch() {
    notImplemented("HubSpot");
  },
});

const pipelineValue = scalar({
  id: "pipeline_value",
  label: "Pipeline value",
  shortLabel: "Pipeline",
  unit: "currency",
  freshnessSeconds: 300,
  methodology: "Total value of open deals.",

  async fetch() {
    notImplemented("HubSpot");
  },
});

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const hubspot = provider({
  manifest,
  credentialSchema,
  userInputFields: [],
  metrics: [contacts, newContacts, openDeals, wonDeals, pipelineValue],

  async verify() {
    notImplemented("HubSpot");
  },
});
