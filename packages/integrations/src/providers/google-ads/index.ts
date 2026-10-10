import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "google-ads",
  name: "Google Ads",
  category: "marketing",
  tagline: "Spend, clicks and conversions from Google Ads.",
  docsUrl: "https://developers.google.com/google-ads/api/docs/start",
  iconPath: "/connectors/google-ads.svg",
  accentColor: "#4285F4",
  keywords: ["advertising", "ppc", "adwords", "google", "campaigns"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your Google Ads campaigns and performance"],
    requiresSelection: true,
    selectionLabel: "Which account?",
  },
  fields: [],
  metrics: [
    {
      id: "ad_spend",
      label: "Ad spend",
      shortLabel: "Spend",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Amount spent on ads in the window.",
    },
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
      id: "ad_conversions",
      label: "Ad conversions",
      shortLabel: "Conv.",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Conversions attributed to ads in the window.",
    },
  ],
  allowedHosts: ["googleads.googleapis.com", "oauth2.googleapis.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  customer_id: z.string().min(1).optional(),
  access_token: z.string().min(10).optional(),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.number().int().optional(),
});
export type GoogleAdsCredentials = z.infer<typeof credentialSchema>;

/**
 * Tokens arrive from the OAuth callback and are never typed in, which is
 * why `userInputFields` is explicit — without it the connect page would
 * render an access token as a text box.
 */
export const googleAds: ProviderAdapter<GoogleAdsCredentials> = {
  manifest,
  credentialSchema,
  userInputFields: [],
  async verify() {
    notImplemented("Google Ads");
  },
  async fetchMetric() {
    notImplemented("Google Ads");
  },
};
