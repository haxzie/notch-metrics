import type { ProviderManifest } from "@notch/schemas";
import { recentPaymentsDescriptor } from "../../list.ts";
import { paymentReceivedNotification } from "../../notifications.ts";

export const manifest: ProviderManifest = {
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
  metrics: [
    {
      id: "revenue",
      label: "Sales",
      shortLabel: "Sales",
      unit: "currency",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Order totals for orders placed in the window that took payment, in the store's own currency. Gross: a later refund does not remove the order from the day it was placed — the Refunds widget is the other half.",
    },
    {
      id: "orders",
      label: "Orders",
      shortLabel: "Orders",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Orders placed in the window that took payment. Test orders and abandoned or unpaid checkouts are excluded, so this sits below the Shopify admin's own order count when the store has pending orders.",
    },
    {
      id: "average_order_value",
      label: "Average order value",
      shortLabel: "AOV",
      unit: "currency",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      // The headline is the window's own ratio, not the mean of the daily
      // ones: averaging averages weights a Tuesday with two orders the same
      // as a Black Friday with four hundred.
      methodology:
        "Sales divided by orders over the whole window. Each point is that day's own ratio, so the headline is not the average of the points.",
    },
    {
      id: "refunds",
      label: "Refunds",
      shortLabel: "Refunds",
      unit: "currency",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Amounts refunded against orders placed in the window, bucketed by the order's date rather than the refund's. A refund of a much older order is not counted here.",
    },
    {
      id: "new_customers",
      label: "New customers",
      shortLabel: "New",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Customer records created in the window. Shopify creates one at checkout, so a guest who buys twice counts once — but somebody who only signed up for the newsletter counts too.",
    },
    {
      id: "customers",
      label: "Customers",
      shortLabel: "Customers",
      unit: "count",
      granularities: ["day"],
      supportsSeries: false,
      supportsCompare: false,
      methodology:
        "Every customer record on the store right now, which is what the admin's Customers page counts. Shopify reports this as an estimate above ten thousand.",
    },
    recentPaymentsDescriptor(
      "The latest orders that took payment, newest first, with the buyer's name and the first product on the order. The headline is their total in the store's currency.",
    ),
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
