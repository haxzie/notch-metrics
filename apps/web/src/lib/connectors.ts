/**
 * The connector catalogue, as the marketing pages show it.
 *
 * A static copy of what `GET /v1/connectors` returns rather than a fetch: the
 * home page is rendered at build and must look complete with no API
 * reachable, and a launch announcement should not depend on the Worker
 * being up. The names, colours and statuses mirror the manifests in
 * `packages/integrations`; a provider that ships there is one line here.
 */
export interface MarketingConnector {
  id: string;
  name: string;
  accentColor: string;
  /**
   * The manifest's own three states, not two.
   *
   * `beta` used to be flattened to `coming_soon` here, which showed Google
   * Analytics and Search Console as "Soon" for as long as they had been
   * connectable — the server lists anything that is not `coming_soon`, so
   * the site was the only thing saying they did not work.
   */
  status: "stable" | "beta" | "coming_soon";
}

export interface ConnectorGroup {
  label: string;
  connectors: MarketingConnector[];
}

export const CONNECTOR_GROUPS: ConnectorGroup[] = [
  {
    label: "Revenue",
    connectors: [
      { id: "stripe", name: "Stripe", accentColor: "#635BFF", status: "stable" },
      { id: "polar", name: "Polar", accentColor: "#090909", status: "stable" },
      { id: "paddle", name: "Paddle", accentColor: "#FDDD35", status: "stable" },
      { id: "dodopayments", name: "Dodo Payments", accentColor: "#111111", status: "stable" },
      { id: "lemonsqueezy", name: "Lemon Squeezy", accentColor: "#FFC233", status: "stable" },
      { id: "revenuecat", name: "RevenueCat", accentColor: "#F2545B", status: "stable" },
      { id: "shopify", name: "Shopify", accentColor: "#7AB55C", status: "beta" },
    ],
  },
  {
    label: "Developer",
    connectors: [{ id: "github", name: "GitHub", accentColor: "#181717", status: "stable" }],
  },
  {
    label: "Product analytics",
    connectors: [
      { id: "posthog", name: "PostHog", accentColor: "#1D1D1D", status: "beta" },
      { id: "plausible", name: "Plausible", accentColor: "#5850EC", status: "beta" },
      { id: "mixpanel", name: "Mixpanel", accentColor: "#7856FF", status: "coming_soon" },
      { id: "amplitude", name: "Amplitude", accentColor: "#1E61F0", status: "beta" },
      {
        id: "google-analytics",
        name: "Google Analytics",
        accentColor: "#E8710A",
        status: "beta",
      },
    ],
  },
  {
    label: "Marketing & SEO",
    connectors: [
      {
        id: "google-search-console",
        name: "Search Console",
        accentColor: "#4285F4",
        status: "beta",
      },
      { id: "youtube", name: "YouTube", accentColor: "#FF0000", status: "beta" },
      { id: "google-ads", name: "Google Ads", accentColor: "#4285F4", status: "coming_soon" },
      { id: "meta-ads", name: "Meta Ads", accentColor: "#0866FF", status: "coming_soon" },
    ],
  },
  {
    label: "CRM",
    connectors: [
      { id: "hubspot", name: "HubSpot", accentColor: "#FF7A59", status: "coming_soon" },
      { id: "intercom", name: "Intercom", accentColor: "#1F8DED", status: "coming_soon" },
    ],
  },
];

/** What a visitor can connect today — which is everything not `coming_soon`. */
export const LIVE_CONNECTORS = CONNECTOR_GROUPS.flatMap((group) =>
  group.connectors.filter((connector) => connector.status !== "coming_soon"),
);
