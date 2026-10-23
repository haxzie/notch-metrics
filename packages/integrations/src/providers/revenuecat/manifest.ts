import type { ProviderManifest } from "@notch/schemas";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "revenuecat",
  name: "RevenueCat",
  category: "revenue",
  tagline: "In-app subscription revenue, subscribers and trials from RevenueCat.",
  docsUrl: "https://www.revenuecat.com/docs/projects/authentication",
  dashboardUrl: "https://app.revenuecat.com",
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
  allowedHosts: ["api.revenuecat.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
