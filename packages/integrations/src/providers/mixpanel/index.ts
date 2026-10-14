import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "mixpanel",
  name: "Mixpanel",
  category: "analytics",
  tagline: "Events and active users from Mixpanel.",
  docsUrl: "https://developer.mixpanel.com/reference/service-accounts",
  dashboardUrl: "https://mixpanel.com",
  iconPath: "/connectors/mixpanel.svg",
  accentColor: "#7856FF",
  keywords: ["product analytics", "events", "funnels"],
  authMode: "api_key",
  fields: [
    {
      key: "username",
      label: "Service account username",
      type: "string",
      required: true,
      help: "Organization Settings \u2192 Service Accounts.",
    },
    {
      key: "secret",
      label: "Service account secret",
      type: "secret",
      required: true,
    },
    {
      key: "project_id",
      label: "Project ID",
      type: "string",
      required: true,
      help: "Project Settings \u2192 Project Details.",
    },
    {
      key: "region",
      label: "Data residency",
      type: "select",
      required: true,
      help: "EU projects reject requests to the US host.",
      options: [
        { value: "us", label: "United States" },
        { value: "eu", label: "European Union" },
      ],
      default: "us",
    },
  ],
  metrics: [
    {
      id: "active_users",
      label: "Active users",
      shortLabel: "Users",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Users with at least one event in the window.",
    },
    {
      id: "new_users",
      label: "New users",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Users seen for the first time in the window.",
    },
    {
      id: "events",
      label: "Events",
      shortLabel: "Events",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Events recorded in the window.",
    },
  ],
  allowedHosts: ["mixpanel.com", "eu.mixpanel.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  username: z.string().min(1),
  secret: z.string().min(8),
  project_id: z.string().min(1),
  region: z.enum(["us", "eu"]).default("us"),
});
export type MixpanelCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const mixpanel: ProviderAdapter<MixpanelCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Mixpanel");
  },
  async fetchMetric() {
    notImplemented("Mixpanel");
  },
};
