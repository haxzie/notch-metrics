import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";

export const manifest: ProviderManifest = {
  id: "polar",
  name: "Polar",
  category: "revenue",
  tagline: "Revenue and subscriptions from your Polar storefront.",
  docsUrl: "https://polar.sh/docs/integrate/authentication",
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
        "Polar's own MRR: active subscriptions normalised to a month, yearly plans divided by twelve, trials excluded. The latest day Polar has computed.",
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
        "Order subtotals in the window as Polar reports them, before Polar's fees and before tax. In the organization's currency.",
    },
    {
      id: "active_subscribers",
      label: "Active subscriptions",
      shortLabel: "Active",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "Active subscriptions on the latest day Polar has computed, including paused and past-due ones, excluding trials.",
    },
    {
      id: "new_subscribers",
      label: "New subscriptions",
      shortLabel: "New",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions started in the window, as Polar counts them.",
    },
    {
      id: "churned_subscribers",
      label: "Churned subscriptions",
      shortLabel: "Churn",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Subscriptions that ended in the window, as Polar counts them.",
    },
    recentPaymentsDescriptor(
      "The latest paid orders, newest first, with the customer's name or email and the product. Amounts are what the customer paid, after discounts and including tax.",
    ),
  ],
  allowedHosts: ["api.polar.sh", "sandbox-api.polar.sh"],
  status: "stable",
  minAppVersion: "0.1.0",
};
