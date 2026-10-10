import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "amplitude",
  name: "Amplitude",
  category: "analytics",
  tagline: "Active users and events from Amplitude.",
  docsUrl: "https://amplitude.com/docs/apis/authentication",
  iconPath: "/connectors/amplitude.svg",
  accentColor: "#1E61F0",
  keywords: ["product analytics", "events", "behaviour", "cohorts"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Settings \u2192 Projects \u2192 General.",
    },
    {
      key: "secret_key",
      label: "Secret key",
      type: "secret",
      required: true,
    },
    {
      key: "region",
      label: "Data residency",
      type: "select",
      required: true,
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
  allowedHosts: ["amplitude.com", "analytics.eu.amplitude.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  secret_key: z.string().min(8),
  region: z.enum(["us", "eu"]).default("us"),
});
export type AmplitudeCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const amplitude: ProviderAdapter<AmplitudeCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Amplitude");
  },
  async fetchMetric() {
    notImplemented("Amplitude");
  },
};
