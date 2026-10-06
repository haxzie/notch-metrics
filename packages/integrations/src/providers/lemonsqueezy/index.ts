import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "lemonsqueezy",
  name: "Lemon Squeezy",
  category: "revenue",
  tagline: "Store revenue and subscriptions from Lemon Squeezy.",
  docsUrl: "https://app.lemonsqueezy.com/settings/api",
  iconPath: "/providers/lemonsqueezy.svg",
  accentColor: "#FFC233",
  authMode: "api_key",
  fields: [
    { key: "api_key", label: "API key", type: "secret", required: true },
    {
      key: "store_id",
      label: "Store ID",
      type: "string",
      required: false,
      help: "Leave empty to total every store on the account.",
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
      methodology: "Paid orders in the window, by total.",
    },
  ],
  allowedHosts: ["api.lemonsqueezy.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(20),
  store_id: z.string().optional(),
});
export type LemonSqueezyCredentials = z.infer<typeof credentialSchema>;

export const lemonsqueezy: ProviderAdapter<LemonSqueezyCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    throw new ProviderError("unsupported", "The Lemon Squeezy integration is not ready yet.");
  },
  async fetchMetric() {
    throw new ProviderError("unsupported", "The Lemon Squeezy integration is not ready yet.");
  },
};
