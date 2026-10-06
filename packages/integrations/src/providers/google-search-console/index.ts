import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "google-search-console",
  name: "Google Search Console",
  category: "marketing",
  tagline: "Clicks, impressions and ranking from Search Console.",
  docsUrl: "https://search.google.com/search-console",
  iconPath: "/providers/google-search-console.svg",
  accentColor: "#4285F4",
  keywords: ["gsc", "seo", "search", "google", "rankings", "queries"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your Search Console performance data"],
    requiresSelection: true,
    selectionLabel: "Which property?",
  },
  fields: [],
  metrics: [
    {
      id: "clicks",
      label: "Clicks",
      shortLabel: "Clicks",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Clicks through to the site in the window.",
    },
    {
      id: "impressions",
      label: "Impressions",
      shortLabel: "Impr.",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Times a result was shown in the window.",
    },
    {
      id: "ctr",
      label: "Click-through rate",
      shortLabel: "CTR",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Clicks divided by impressions.",
    },
    {
      id: "average_position",
      label: "Average position",
      shortLabel: "Position",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Mean ranking position across impressions. Lower is better.",
    },
  ],
  allowedHosts: ["searchconsole.googleapis.com", "oauth2.googleapis.com", "www.googleapis.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  site: z.string().min(1).optional(),
  access_token: z.string().min(10).optional(),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.number().int().optional(),
});
export type GoogleSearchConsoleCredentials = z.infer<typeof credentialSchema>;

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const googleSearchConsole: ProviderAdapter<GoogleSearchConsoleCredentials> = {
  manifest,
  credentialSchema,
  userInputFields: [],
  async verify() {
    notImplemented("Google Search Console");
  },
  async fetchMetric() {
    notImplemented("Google Search Console");
  },
};
