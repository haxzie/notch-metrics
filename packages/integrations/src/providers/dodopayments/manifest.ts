import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: ProviderManifest = {
  id: "dodopayments",
  name: "Dodo Payments",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Dodo Payments account.",
  docsUrl: "https://app.dodopayments.com/developer/api-keys",
  dashboardUrl: "https://app.dodopayments.com",
  iconPath: "/connectors/dodopayments.svg",
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
    // "Total" and "One-time", not "Revenue" and "Sales": Dodo sells both
    // subscriptions and single purchases through the same payments list, and
    // a tile that just said "Revenue" left the user guessing which of the
    // two it counted.
    {
      id: "revenue",
      label: "Total revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Every succeeded payment in the window, subscription renewals and one-time purchases together, by `total_amount`. Gross — before refunds and fees.",
    },
    {
      id: "one_time_sales",
      label: "One-time sales",
      shortLabel: "One-time",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Succeeded payments in the window that are not tied to a subscription, by `total_amount`. Gross — before refunds and fees.",
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
    recentPaymentsDescriptor(
      "The latest succeeded payments, newest first, with the customer's name or email. The headline is their total in your currency.",
    ),
  ],
  notifications: [
    paymentReceivedNotification("A payment that succeeded, including subscription renewals."),
  ],
  allowedHosts: ["live.dodopayments.com", "test.dodopayments.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
