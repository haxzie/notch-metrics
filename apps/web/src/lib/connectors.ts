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
  status: "stable" | "coming_soon";
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
      { id: "polar", name: "Polar", accentColor: "#0062FF", status: "stable" },
      { id: "paddle", name: "Paddle", accentColor: "#FDDD35", status: "stable" },
      { id: "dodopayments", name: "Dodo Payments", accentColor: "#111111", status: "stable" },
      { id: "lemonsqueezy", name: "Lemon Squeezy", accentColor: "#FFC233", status: "stable" },
      { id: "revenuecat", name: "RevenueCat", accentColor: "#F2545B", status: "stable" },
    ],
  },
  {
    label: "Developer",
    connectors: [{ id: "github", name: "GitHub", accentColor: "#181717", status: "stable" }],
  },
  {
    label: "Product analytics",
    connectors: [
      { id: "posthog", name: "PostHog", accentColor: "#F54E00", status: "coming_soon" },
      { id: "plausible", name: "Plausible", accentColor: "#5850EC", status: "coming_soon" },
      { id: "mixpanel", name: "Mixpanel", accentColor: "#7856FF", status: "coming_soon" },
      { id: "amplitude", name: "Amplitude", accentColor: "#1E61F0", status: "coming_soon" },
      {
        id: "google-analytics",
        name: "Google Analytics",
        accentColor: "#E8710A",
        status: "coming_soon",
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
        status: "coming_soon",
      },
      { id: "ahrefs", name: "Ahrefs", accentColor: "#FF8C00", status: "coming_soon" },
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

export const LIVE_CONNECTORS = CONNECTOR_GROUPS.flatMap((group) =>
  group.connectors.filter((connector) => connector.status === "stable"),
);
