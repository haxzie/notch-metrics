import type { ProviderManifest } from "@notch/schemas";

export const manifest: ProviderManifest = {
  id: "revenuecat",
  name: "RevenueCat",
  category: "revenue",
  tagline: "In-app subscription revenue, subscribers and trials from RevenueCat.",
  docsUrl: "https://www.revenuecat.com/docs/projects/authentication",
  iconPath: "/connectors/revenuecat.svg",
  accentColor: "#F2545B",
  keywords: ["in-app purchases", "iap", "app store", "play store", "subscriptions", "mobile"],
  authMode: "api_key",
  fields: [
    {
      key: "secret_key",
      label: "Secret API key (v2)",
      type: "secret",
      required: true,
      help: "Project settings → API keys → New, version V2. Grant Charts & Metrics read; add Projects read to pick the project by name.",
    },
    {
      key: "project_id",
      label: "Project ID",
      type: "string",
      required: false,
      placeholder: "proj1ab2c3d4",
      help: "Required when the key can see more than one project, or cannot list projects at all.",
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
        "RevenueCat's own MRR figure for the project: active paid subscriptions normalised to a month, as shown on the Overview. A snapshot of the book right now.",
    },
    {
      id: "revenue",
      label: "Revenue",
      shortLabel: "Revenue",
      unit: "currency",
      granularities: ["day", "week", "month"],
      // RevenueCat's total endpoint answers one window at a time, so the delta
      // is a second call and a sparkline is not available without a chart walk.
      supportsSeries: false,
      supportsCompare: true,
      methodology:
        "Gross revenue across every app in the project for the days in the window, before store commission and taxes. Today is partial while transactions are still arriving.",
    },
    {
      id: "active_subscribers",
      label: "Active subscriptions",
      shortLabel: "Active subs",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "Paid subscriptions active right now, including ones that are cancelled or in a grace period until they expire. Trials are not counted.",
    },
    {
      id: "trials",
      label: "Active trials",
      shortLabel: "Trials",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "Free trials active right now, including cancelled ones, until they convert to paid or expire.",
    },
    {
      id: "new_users",
      label: "New customers · 28 days",
      shortLabel: "New · 28d",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "App User IDs first seen in the last 28 days, as RevenueCat's Overview counts them. The window is fixed by RevenueCat and ignores the widget's range. Aliased IDs count once.",
    },
    {
      id: "active_users",
      label: "Active customers · 28 days",
      shortLabel: "Active · 28d",
      unit: "count",
      granularities: ["day", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "App User IDs that contacted RevenueCat in the last 28 days. The window is fixed by RevenueCat and ignores the widget's range. May lag by one to two hours.",
    },
  ],
  allowedHosts: ["api.revenuecat.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
