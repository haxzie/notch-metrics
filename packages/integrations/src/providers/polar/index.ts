import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "polar",
  name: "Polar",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Polar storefront.",
  docsUrl: "https://polar.sh/settings",
  iconPath: "/providers/polar.svg",
  accentColor: "#0062FF",
  keywords: ["payments", "billing", "open source", "storefront"],
  authMode: "api_key",
  fields: [
    {
      key: "access_token",
      label: "Access token",
      type: "secret",
      required: true,
      help: "Settings → Developers. A read-only token is enough.",
    },
  ],
  metrics: [
    {
      id: "mrr",
      label: "Monthly recurring revenue",
      shortLabel: "MRR",
      unit: "currency",
      granularities: ["day", "month"],
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
      methodology: "Succeeded orders in the window.",
    },
  ],
  allowedHosts: ["api.polar.sh"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({ access_token: z.string().min(20) });
export type PolarCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented.
 *
 * `status: "coming_soon"` is what the settings UI reads to list it and grey it
 * out. Returning zeroes instead would look like a working integration
 * reporting a dead business — and the adapter exists at all so the registry
 * stays a total record over `ProviderId`, which is what makes a missing
 * adapter a compile error rather than a runtime one.
 */
export const polar: ProviderAdapter<PolarCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    throw new ProviderError("unsupported", "The Polar integration is not ready yet.");
  },
  async fetchMetric() {
    throw new ProviderError("unsupported", "The Polar integration is not ready yet.");
  },
};
