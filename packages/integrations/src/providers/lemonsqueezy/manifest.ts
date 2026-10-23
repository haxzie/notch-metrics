import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
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
  notifications: [
    paymentReceivedNotification("An order marked paid. Subscription renewals count."),
  ],
  allowedHosts: ["api.lemonsqueezy.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
