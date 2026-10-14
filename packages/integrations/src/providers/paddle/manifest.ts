import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: ProviderManifest = {
  id: "paddle",
  name: "Paddle",
  category: "revenue",
  tagline: "Subscriptions and revenue from Paddle Billing.",
  docsUrl: "https://developer.paddle.com/api-reference/about/authentication",
  dashboardUrl: "https://vendors.paddle.com",
  iconPath: "/connectors/paddle.svg",
  accentColor: "#FDDD35",
  keywords: ["payments", "billing", "merchant of record", "subscriptions"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      placeholder: "pdl_live_apikey_…",
      help: "Developer Tools → Authentication. Read permission on transactions, subscriptions and customers is enough.",
    },
    {
      key: "mode",
      label: "Environment",
      type: "select",
      required: true,
      help: "Must match where the key was issued; a live key against the sandbox is rejected as invalid.",
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
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      freshnessSeconds: 180,
      methodology:
        "Active subscriptions, each recurring item's unit price times quantity normalised to a month by its billing cycle. Discounts are not applied. A snapshot of the book right now.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 60,
      methodology:
        "Transactions billed in the window that are paid or completed, by their total including tax, before Paddle's fee. Bucketed by billing date.",
    },
    {
      id: "active_subscribers",
      label: "Active subscriptions",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      freshnessSeconds: 180,
      methodology:
        "Subscriptions in status `active` right now. Trialing and paused are not counted.",
    },
    {
      id: "new_subscribers",
      label: "New subscriptions",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 180,
      methodology:
        "Subscriptions whose `started_at` falls in the window, in any status. Paddle cannot filter subscriptions by date, so the whole list is read and bounded.",
    },
    {
      id: "churned_subscribers",
      label: "Churned subscriptions",
      shortLabel: "Churn",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 180,
      methodology:
        "Subscriptions whose `canceled_at` falls in the window. Paddle cannot filter subscriptions by date, so the whole list is read and bounded.",
    },
    recentPaymentsDescriptor(
      "The latest paid or completed transactions by billing date, with the customer's name or email and the first product on the transaction. Totals include tax.",
    ),
  ],
  notifications: [
    paymentReceivedNotification(
      "A completed transaction. Paddle's own retries are collapsed into the success.",
    ),
  ],
  allowedHosts: ["api.paddle.com", "sandbox-api.paddle.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
