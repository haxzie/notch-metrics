import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";
import { paymentReceivedNotification, metricThresholdNotification } from "../../notifications.ts";

export const manifest: ProviderManifest = {
  id: "stripe",
  name: "Stripe",
  category: "revenue",
  tagline: "Revenue, MRR and subscribers straight from your Stripe account.",
  docsUrl: "https://dashboard.stripe.com/apikeys",
  dashboardUrl: "https://dashboard.stripe.com",
  iconPath: "/connectors/stripe.svg",
  accentColor: "#635BFF",
  keywords: ["payments", "billing", "checkout", "subscriptions", "revenue"],
  authMode: "api_key",
  fields: [
    {
      key: "secret_key",
      label: "Secret key",
      type: "secret",
      required: true,
      placeholder: "rk_live_…",
      // Pushing restricted keys is the cheapest reduction of the blast radius
      // in the whole product: a read-only key cannot move money if we leak it.
      help: "A restricted key with read access to Charges and Subscriptions is enough, and is safer than a full secret key.",
      pattern: "^(sk|rk)_(live|test)_[A-Za-z0-9]+$",
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
      methodology:
        "Active subscriptions right now, each item normalised to a monthly amount (annual ÷ 12, weekly × 52/12) and reduced by any percentage coupon. A snapshot, not a sum over the window.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Gross charges from balance transactions in the window, before Stripe fees. Refunds are reported separately rather than netted off.",
    },
    {
      id: "active_subscribers",
      label: "Active subscribers",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Subscriptions in Stripe status `active` right now. Trials are not counted.",
    },
    {
      id: "new_subscribers",
      label: "New subscribers",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions created in the window, bucketed by creation time.",
    },
    {
      id: "churned_subscribers",
      label: "Churned subscribers",
      shortLabel: "Churn",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions cancelled in the window, bucketed by cancellation time.",
    },
    {
      id: "refunds",
      label: "Refunds",
      shortLabel: "Refunds",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Refund balance transactions in the window, as a positive amount.",
    },
    recentPaymentsDescriptor(
      "The latest succeeded charges, newest first, with the payer's billing name or receipt email and the charge description. The headline is their total in your currency.",
    ),
  ],
  notifications: [
    paymentReceivedNotification(
      "A charge that succeeded. One that fails and is later retried successfully arrives once, when it succeeds.",
    ),
    {
      id: "payment_failed",
      kind: "event",
      label: "Failed payment",
      shortLabel: "Failed payment",
      severity: "warning",
      methodology:
        "A charge Stripe declined, with the reason it gave. A charge that fails and is " +
        "then retried successfully still arrives once, when it fails.",
      source: { from: "adapter_events", stream: "charges" },
      // The one notification worth interrupting somebody for, and the reason
      // most people turn this feature on at all.
      defaultEnabled: true,
      userConfigurable: true,
      minIntervalSeconds: 60,
      maxBurst: 5,
    },
    {
      id: "refund_issued",
      kind: "event",
      label: "Refund issued",
      shortLabel: "Refund",
      severity: "info",
      methodology:
        "A charge refunded in full or in part. The amount shown is what was refunded, " +
        "not what was originally charged.",
      source: { from: "adapter_events", stream: "charges" },
      defaultEnabled: false,
      userConfigurable: true,
      minIntervalSeconds: 60,
      maxBurst: 5,
    },
    metricThresholdNotification({
      metric: "mrr",
      unit: "currency",
      label: "MRR crosses a figure",
      suggestedValue: 1_000_000,
      methodology:
        "Checked against the same monthly recurring revenue figure the tile shows, so it can be announced on a reading up to fifteen minutes old.",
    }),
  ],
  allowedHosts: ["api.stripe.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
