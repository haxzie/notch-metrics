import type { ProviderManifest } from "@notch/schemas";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "shopify",
  name: "Shopify",
  category: "revenue",
  tagline: "Sales, orders and customers from your Shopify store.",
  docsUrl: "https://help.shopify.com/en/manual/apps/app-types/custom-apps",
  dashboardUrl: "https://admin.shopify.com",
  iconPath: "/connectors/shopify.svg",
  accentColor: "#7AB55C",
  keywords: ["ecommerce", "e-commerce", "store", "shop", "orders", "retail", "commerce"],
  authMode: "api_key",
  fields: [
    {
      key: "shop_domain",
      label: "Store domain",
      type: "string",
      required: true,
      placeholder: "my-store.myshopify.com",
      // The vanity domain a store serves its storefront on is not routable
      // for the Admin API, and pasting one answers 404 on every call — which
      // reads as a deleted store rather than the wrong hostname.
      help: "The .myshopify.com domain, not your custom storefront domain. Settings → Domains.",
      pattern: "^[a-zA-Z0-9][a-zA-Z0-9-]*(\\.myshopify\\.com)?$",
    },
    {
      key: "access_token",
      label: "Admin API access token",
      type: "secret",
      required: true,
      placeholder: "shpat_…",
      help: "Settings → Apps and sales channels → Develop apps → your app → API credentials. Scopes: read_orders, read_customers, read_products.",
      pattern: "^shp(at|ca)_[A-Za-z0-9]+$",
    },
  ],
  setupSteps: [
    { text: "Open Settings, then Apps and sales channels." },
    { text: "Select Develop apps, then create an app." },
    { text: "Give it read_orders, read_customers and read_products." },
    { text: "Install the app, then open API credentials." },
    { text: "Copy the Admin API access token, then paste it above." },
    { text: "Your store domain ends .myshopify.com, not your custom domain." },
  ],
  // One wildcard label deep, which is exactly what a shop domain is. The
  // allowlist is re-checked on every redirect hop, so a store that has been
  // renamed and 30x-es to its new domain fails here rather than replaying the
  // Admin token at whatever answered.
  notifications: [
    paymentReceivedNotification(
      "A paid order. An order placed but unpaid is not announced until it is paid.",
    ),
  ],
  allowedHosts: ["*.myshopify.com"],
  status: "beta",
  minAppVersion: "0.1.0",
};
