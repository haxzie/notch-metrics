import type { ProviderManifest } from "@notch/schemas";

export const manifest: ProviderManifest = {
  id: "dodopayments",
  name: "Dodo Payments",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Dodo Payments account.",
  docsUrl: "https://app.dodopayments.com/developer/api-keys",
  iconPath: "/providers/dodopayments.svg",
  accentColor: "#111111",
  keywords: ["payments", "billing", "merchant of record", "subscriptions", "dodo"],
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
        "Active subscriptions, each `recurring_pre_tax_amount` normalised to a monthly amount using its payment frequency. A snapshot of the book right now, not a total over the window.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Succeeded payments in the window, by `total_amount`. Gross — before refunds and fees.",
    },
    {
      id: "active_subscribers",
      label: "Active subscribers",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Subscriptions in status `active` right now.",
    },
  ],
  allowedHosts: ["live.dodopayments.com", "test.dodopayments.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
