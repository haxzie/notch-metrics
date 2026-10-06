import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "paddle",
  name: "Paddle",
  category: "revenue",
  tagline: "Subscriptions and revenue from Paddle Billing.",
  docsUrl: "https://vendors.paddle.com/authentication-v2",
  iconPath: "/providers/paddle.svg",
  accentColor: "#FDDD35",
  keywords: ["payments", "billing", "merchant of record", "subscriptions"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Developer Tools \u2192 Authentication. A read-only key is enough.",
    },
    {
      key: "mode",
      label: "Environment",
      type: "select",
      required: true,
      help: "Must match where the key was issued; a live key against sandbox returns 403.",
      options: [
        { value: "live", label: "Live" },
        { value: "sandbox", label: "Sandbox" },
      ],
      default: "live",
    },
  ],
  metrics: [
    {
      id: "mrr",
      label: "Monthly recurring revenue",
      shortLabel: "MRR",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Active subscriptions normalised to a monthly amount.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Gross transactions in the window, before fees.",
    },
    {
      id: "active_subscribers",
      label: "Active subscribers",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Subscriptions currently in an active state.",
    },
    {
      id: "new_subscribers",
      label: "New subscribers",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions created in the window.",
    },
    {
      id: "churned_subscribers",
      label: "Churned subscribers",
      shortLabel: "Churn",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions cancelled in the window.",
    },
  ],
  allowedHosts: ["api.paddle.com", "sandbox-api.paddle.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  mode: z.enum(["live", "sandbox"]).default("live"),
});
export type PaddleCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * business.
 */
export const paddle: ProviderAdapter<PaddleCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("Paddle");
  },
  async fetchMetric() {
    notImplemented("Paddle");
  },
};
