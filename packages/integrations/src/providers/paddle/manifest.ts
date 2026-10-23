import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
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
  notifications: [
    paymentReceivedNotification(
      "A completed transaction. Paddle's own retries are collapsed into the success.",
    ),
  ],
  allowedHosts: ["api.paddle.com", "sandbox-api.paddle.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
