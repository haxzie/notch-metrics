import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "google-analytics",
  name: "Google Analytics",
  tagline: "Visitors, sessions and conversions from GA4.",
  docsUrl: "https://analytics.google.com/analytics/web/",
  iconPath: "/providers/google-analytics.svg",
  accentColor: "#E8710A",
  // The only provider here that cannot work with a pasted key: GA4's Data API
  // is OAuth-only, so connecting one needs the authorisation flow that
  // `authMode` exists to signal. The settings UI branches on this.
  authMode: "oauth2",
  fields: [
    {
      key: "property_id",
      label: "Property ID",
      type: "string",
      required: true,
      help: "Admin → Property Settings. A number like 123456789.",
    },
  ],
  metrics: [
    {
      id: "active_subscribers",
      label: "Active users",
      shortLabel: "Users",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "GA4 `activeUsers` over the window, for the selected property.",
    },
    {
      id: "new_subscribers",
      label: "New users",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "GA4 `newUsers`, bucketed by first session.",
    },
  ],
  allowedHosts: ["analyticsdata.googleapis.com", "oauth2.googleapis.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  property_id: z.string().regex(/^\d+$/, "A GA4 property ID is a number."),
  // Written by the OAuth callback, never by the settings form.
  refresh_token: z.string().min(20).optional(),
});
export type GoogleAnalyticsCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. See the note in `polar/index.ts`.
 *
 * This one additionally needs the OAuth routes that `authMode: "oauth2"`
 * implies and that `/v1/integrations` does not yet have.
 */
export const googleAnalytics: ProviderAdapter<GoogleAnalyticsCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    throw new ProviderError("unsupported", "Google Analytics needs OAuth, which is not ready yet.");
  },
  async fetchMetric() {
    throw new ProviderError("unsupported", "Google Analytics needs OAuth, which is not ready yet.");
  },
};
