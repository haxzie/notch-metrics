import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification, metricThresholdNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
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
      //
      // This used to name Charges and Subscriptions, which is the set a
      // careful person then ticks one by one — and that key cannot read
      // `/v1/account`, which is the first call `verify` makes. The connection
      // failed with a bare 403 and the user rebuilt the key four times. Read
      // on the two groups is the same blast radius and actually works.
      help: "A restricted key with read access to all core and billing resources is enough, and is safer than a full secret key.",
      pattern: "^(sk|rk)_(live|test)_[A-Za-z0-9]+$",
    },
  ],
  // The group toggles rather than a list of individual resources. Picking
  // resources one by one is what produced the support ticket this was written
  // for: a key with Charges and Subscriptions ticked still cannot read
  // `/v1/account`, which is the first call `verify` makes, so the whole
  // connection failed on a key the user had every reason to think was right.
  setupSteps: [
    {
      text: "Open the API keys page in your Stripe dashboard.",
      url: "https://dashboard.stripe.com/apikeys",
    },
    { text: "Select Create restricted key." },
    { text: "Set All core resources and All billing resources to Read." },
    { text: "Leave everything else at None. Notch Metrics only reads." },
    { text: "Copy the key, then paste it above." },
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
