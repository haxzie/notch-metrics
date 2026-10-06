import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "posthog",
  name: "PostHog",
  category: "analytics",
  tagline: "Product analytics \u2014 users, events and conversion from PostHog.",
  docsUrl: "https://posthog.com/docs/api#personal-api-keys",
  iconPath: "/providers/posthog.svg",
  accentColor: "#F54E00",
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "Personal API key",
      type: "secret",
      required: true,
      help: "Settings \u2192 Personal API keys. Needs only project read access.",
    },
    {
      key: "project_id",
      label: "Project ID",
      type: "string",
      required: true,
      help: "The number in your PostHog project URL.",
    },
    {
      key: "region",
      label: "Region",
      type: "select",
      required: true,
      help: "PostHog Cloud US or EU. The wrong one returns 401.",
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
    {
      id: "pageviews",
      label: "Pageviews",
      shortLabel: "Views",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Total pages viewed in the window.",
    },
    {
      id: "conversion_rate",
      label: "Conversion rate",
      shortLabel: "Conv.",
      unit: "ratio",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Share of sessions reaching the configured goal.",
    },
  ],
  allowedHosts: ["us.posthog.com", "eu.posthog.com", "app.posthog.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  project_id: z.string().min(1),
  region: z.enum(["us", "eu"]).default("us"),
});
export type PosthogCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const posthog: ProviderAdapter<PosthogCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("PostHog");
  },
  async fetchMetric() {
    notImplemented("PostHog");
  },
};
