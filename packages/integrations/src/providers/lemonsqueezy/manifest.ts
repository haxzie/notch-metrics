import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: ProviderManifest = {
  id: "lemonsqueezy",
  name: "Lemon Squeezy",
  category: "revenue",
  tagline: "Store revenue and subscriptions from Lemon Squeezy.",
  docsUrl: "https://app.lemonsqueezy.com/settings/api",
  dashboardUrl: "https://app.lemonsqueezy.com",
  iconPath: "/connectors/lemonsqueezy.svg",
  accentColor: "#FFC233",
  keywords: ["payments", "billing", "merchant of record", "store", "lemon"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Settings → API. A key is read-write; Lemon Squeezy has no read-only option.",
    },
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
      freshnessSeconds: 180,
      methodology:
        "Active subscriptions, each price normalised to a monthly amount by its renewal interval. A snapshot of the book right now, not a total over the window.",
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
        "Orders in the window that took payment, by `total`. Gross: a later refund does not remove the order from the day it was paid.",
    },
    {
      id: "active_subscribers",
      label: "Active subscribers",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      freshnessSeconds: 180,
      methodology: "Subscriptions in status `active` right now, trials included.",
    },
    {
      id: "refunds",
      label: "Refunds",
      shortLabel: "Refunds",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      // Bucketed by the order's own date, because Lemon Squeezy does not
      // expose when the refund happened — only that it did and for how much.
      freshnessSeconds: 60,
      methodology:
        "`refunded_amount` on orders in the window, bucketed by the order date rather than the refund date, which the API does not expose.",
    },
    recentPaymentsDescriptor(
      "The latest orders that took payment, newest first, with the buyer's name or email and the first product on the order. The headline is their total in your currency.",
    ),
  ],
  notifications: [
    paymentReceivedNotification("An order marked paid. Subscription renewals count."),
  ],
  allowedHosts: ["api.lemonsqueezy.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
