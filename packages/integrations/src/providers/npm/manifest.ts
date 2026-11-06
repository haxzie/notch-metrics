import type { ProviderManifest } from "@notch/schemas";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "npm",
  name: "npm",
  category: "developer",
  tagline: "Downloads for the packages you publish.",
  docsUrl: "https://github.com/npm/registry/blob/master/docs/download-counts.md",
  dashboardUrl: "https://www.npmjs.com",
  iconPath: "/connectors/npm.svg",
  // npm's own red, from the mark.
  accentColor: "#CB3837",
  keywords: ["package", "registry", "node", "javascript", "downloads", "publish"],
  // Nothing to connect. npm publishes download counts to anyone who asks,
  // so a token would buy a trip through 2FA and a name for the connection,
  // and nothing else — and a credential asked for without a use is a
  // credential that can leak for no reason.
  authMode: "none",
  fields: [],
  setupSteps: [
    { text: "Nothing to connect. npm's download counts are public." },
    { text: "Add a widget and name the package it counts." },
    { text: "Private package downloads are not published by npm, so not shown here." },
  ],
  // One host. The registry is not reached at all now that there is no
  // identity to look up.
  allowedHosts: ["api.npmjs.org"],
  status: "stable",
  minAppVersion: "0.1.0",
};
