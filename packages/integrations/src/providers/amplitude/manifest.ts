import type { ProviderManifest } from "@notch/schemas";

export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "amplitude",
  name: "Amplitude",
  category: "analytics",
  tagline: "Active users and events from Amplitude.",
  docsUrl: "https://amplitude.com/docs/apis/authentication",
  dashboardUrl: "https://analytics.amplitude.com",
  iconPath: "/connectors/amplitude.svg",
  accentColor: "#1E61F0",
  keywords: ["product analytics", "events", "behaviour", "cohorts"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "API key",
      type: "secret",
      required: true,
      help: "Settings → Projects → your project → General. Both keys are per project.",
    },
    {
      key: "secret_key",
      label: "Secret key",
      type: "secret",
      required: true,
      help: "Beside the API key. Amplitude signs Dashboard API requests with the pair.",
    },
    {
      key: "region",
      label: "Data residency",
      type: "select",
      required: true,
      // The two regions are separate deployments; a US project's keys simply
      // do not exist in the EU one, which answers 401 like a bad secret.
      help: "An EU project's keys answer 401 on the US host, exactly like a wrong key.",
      options: [
        { value: "us", label: "United States" },
        { value: "eu", label: "European Union" },
      ],
      default: "us",
    },
  ],
  allowedHosts: ["amplitude.com", "analytics.eu.amplitude.com"],
  // Beta until the numbers have been read back against a live project's own
  // charts. Every call here is shaped from Amplitude's documentation rather
  // than from a recorded response.
  status: "beta",
  minAppVersion: "0.1.0",
};
