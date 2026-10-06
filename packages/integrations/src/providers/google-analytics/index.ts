import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "google-analytics",
  name: "Google Analytics",
  category: "analytics",
  tagline: "Visitors, sessions and conversions from GA4.",
  docsUrl: "https://analytics.google.com/analytics/web/",
  iconPath: "/providers/google-analytics.svg",
  accentColor: "#E8710A",
  // The only provider here that cannot work with a pasted key: GA4's Data API
  // is OAuth-only, so connecting one needs the authorisation flow that
  // `authMode` exists to signal. The settings UI branches on this.
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read your Google Analytics reports"],
    // Authorising grants access to every property on the account, so the user
    // still has to say which one this connection is for. Tokens that are
    // valid against nothing in particular are not a working connection.
    requiresSelection: true,
    selectionLabel: "Which property?",
  },
  // Nothing is typed: the property is chosen from a list after authorising,
  // because nobody knows their GA4 property id off the top of their head.
  fields: [],
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
  /** Chosen from the picker after authorising. */
  property_id: z.string().regex(/^\d+$/, "A GA4 property ID is a number.").optional(),
  // Written by the OAuth callback, never by a form.
  access_token: z.string().min(10).optional(),
  refresh_token: z.string().min(10).optional(),
  expires_at: z.number().int().optional(),
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
  // Empty, and explicit. Without it the connect page falls back to rendering
  // every schema field — which would put an access token in a text box.
  userInputFields: [],
  async verify() {
    throw new ProviderError("unsupported", "Google Analytics needs OAuth, which is not ready yet.");
  },
  async fetchMetric() {
    throw new ProviderError("unsupported", "Google Analytics needs OAuth, which is not ready yet.");
  },
};
