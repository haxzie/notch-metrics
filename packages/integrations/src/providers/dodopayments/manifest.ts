import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
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
  notifications: [
    paymentReceivedNotification("A payment that succeeded, including subscription renewals."),
  ],
  allowedHosts: ["live.dodopayments.com", "test.dodopayments.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
