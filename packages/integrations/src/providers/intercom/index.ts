import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "intercom",
  name: "Intercom",
  category: "crm",
  tagline: "Conversation volume and response load from Intercom.",
  docsUrl: "https://developers.intercom.com/docs/build-an-integration/learn-more/authentication",
  iconPath: "/connectors/intercom.svg",
  accentColor: "#1F8DED",
  keywords: ["support", "chat", "inbox", "conversations", "helpdesk"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your conversations and contacts"],
    requiresSelection: false,
  },
  fields: [],
  metrics: [
    {
      id: "open_conversations",
      label: "Open conversations",
      shortLabel: "Open",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Conversations awaiting a reply.",
    },
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

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const intercom: ProviderAdapter<IntercomCredentials> = {
  manifest,
  credentialSchema,
  userInputFields: [],
  async verify() {
    notImplemented("Intercom");
  },
  async fetchMetric() {
    notImplemented("Intercom");
  },
};
