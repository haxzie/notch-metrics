import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "polar",
  name: "Polar",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Polar storefront.",
  docsUrl: "https://polar.sh/docs/integrate/authentication",
  dashboardUrl: "https://polar.sh/dashboard",
  iconPath: "/connectors/polar.svg",
  // Polar has no brand colour: the mark is `currentColor`, black on light
  // and white on dark, over their own near-black. The blue that was here
  // belongs to Polars, the dataframe library at pola.rs.
  accentColor: "#090909",
  keywords: ["payments", "billing", "open source", "storefront", "merchant of record"],
  authMode: "api_key",
  fields: [
    {
      key: "access_token",
      label: "Organization access token",
      type: "secret",
      required: true,
      placeholder: "polar_oat_…",
      help: "Settings → Developers. Needs the organizations:read, metrics:read and orders:read scopes.",
    },
    {
      key: "mode",
      label: "Environment",
      type: "select",
      required: true,
      // The two environments issue tokens with the same prefix, so the host
      // cannot be inferred from the token. A production token against the
      // sandbox answers 401, which reads as a bad token.
      help: "Must match where the token was issued; a production token is rejected by the sandbox.",
      options: [
        { value: "production", label: "Production" },
        { value: "sandbox", label: "Sandbox" },
      ],
      default: "production",
    },
  ],
  notifications: [
    paymentReceivedNotification("An order that completed. Refunds are not announced here."),
  ],
  allowedHosts: ["api.polar.sh", "sandbox-api.polar.sh"],
  status: "stable",
  minAppVersion: "0.1.0",
};
