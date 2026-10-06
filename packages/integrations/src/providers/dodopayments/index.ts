import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { ProviderError } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "dodopayments",
  name: "Dodo Payments",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Dodo Payments account.",
  docsUrl: "https://app.dodopayments.com/developer/api-keys",
  iconPath: "/providers/dodopayments.svg",
  accentColor: "#111111",
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Developer → API keys. A read key is enough.",
    },
    {
      key: "mode",
      label: "Environment",
      type: "select",
      required: true,
      default: "live",
      options: [
        { value: "live", label: "Live" },
        { value: "test", label: "Test" },
      ],
      // Explicit rather than inferred from the key's shape. A live key sent to
      // the test host answers 401, which reads as a bad key rather than the
      // wrong host, and costs an hour to diagnose.
      help: "Must match where the key was issued. Live keys do not work against the test host.",
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
      methodology:
        "Active subscriptions, each `recurring_pre_tax_amount` normalised to a monthly amount using its payment frequency.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Succeeded payments in the window, by `total_amount`.",
    },
    {
      id: "active_subscribers",
      label: "Active subscribers",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Subscriptions in status `active`.",
    },
  ],
  allowedHosts: ["live.dodopayments.com", "test.dodopayments.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  api_key: z.string().min(20),
  mode: z.enum(["test", "live"]).default("live"),
});
export type DodoCredentials = z.infer<typeof credentialSchema>;

/**
 * Not implemented yet, and saying so loudly.
 *
 * The manifest ships with `status: "coming_soon"` so the settings UI lists it
 * and greys it out. Returning fake zeroes here would look like a working
 * integration reporting a dead business.
 */
export const dodopayments: ProviderAdapter<DodoCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    throw new ProviderError("unsupported", "The Dodo Payments integration is not ready yet.");
  },
  async fetchMetric() {
    throw new ProviderError("unsupported", "The Dodo Payments integration is not ready yet.");
  },
};
