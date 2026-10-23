import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import { metricsFor, provider } from "../../metric.ts";
import { notImplemented } from "../../types.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "intercom",
  name: "Intercom",
  category: "crm",
  tagline: "Conversation volume and response load from Intercom.",
  docsUrl: "https://developers.intercom.com/docs/build-an-integration/learn-more/authentication",
  dashboardUrl: "https://app.intercom.com",
  iconPath: "/connectors/intercom.svg",
  accentColor: "#1F8DED",
  keywords: ["support", "chat", "inbox", "conversations", "helpdesk"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your conversations and contacts"],
    requiresSelection: false,
  },
  fields: [],
  allowedHosts: ["api.intercom.io"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  access_token: z.string().min(10).optional(),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.number().int().optional(),
});
export type IntercomCredentials = z.infer<typeof credentialSchema>;

const { scalar, series } = metricsFor<IntercomCredentials>();

const openConversations = scalar({
  id: "open_conversations",
  label: "Open conversations",
  shortLabel: "Open",
  unit: "count",
  freshnessSeconds: 180,
  methodology: "Conversations awaiting a reply.",

  async fetch() {
    notImplemented("Intercom");
  },
});

const contacts = scalar({
  id: "contacts",
  label: "Contacts",
  shortLabel: "Contacts",
  unit: "count",
  freshnessSeconds: 300,
  methodology: "Total contacts in the CRM.",

  async fetch() {
    notImplemented("Intercom");
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
    notImplemented("Intercom");
  },
});

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const intercom = provider({
  manifest,
  credentialSchema,
  userInputFields: [],
  metrics: [openConversations, contacts, newContacts],

  async verify() {
    notImplemented("Intercom");
  },
});
