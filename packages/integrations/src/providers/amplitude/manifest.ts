import type { ProviderManifest } from "@notch/schemas";

/**
 * Amplitude's Dashboard REST API buckets by whole days in the project's
 * timezone, and offers hourly only on some of its charts.
 *
 * So every metric here is asked for daily and rolled up locally, and `hour`
 * is not offered at all rather than offered and silently served as a day.
 */
const ZONE_NOTE =
  "Days are your Amplitude project's timezone, so the figures match its own charts.";

export const manifest: ProviderManifest = {
  id: "amplitude",
  name: "Amplitude",
  category: "analytics",
  tagline: "Active users and events from Amplitude.",
  docsUrl: "https://amplitude.com/docs/apis/authentication",
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
  metrics: [
    {
      id: "active_users",
      label: "Active users",
      shortLabel: "Users",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Users who did anything in the window — Amplitude's "Any Active Event". The headline is Amplitude's own de-duplicated figure for the whole window, so the bars do not add up to it: one person active on three days is one user and three bars. ${ZONE_NOTE}`,
    },
    {
      id: "new_users",
      label: "New users",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Users whose first ever event Amplitude recorded in the window. A user is new on exactly one day, so these bars do add up to the headline. ${ZONE_NOTE}`,
    },
    {
      id: "events",
      label: "Events",
      shortLabel: "Events",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: `Every event recorded in the window, of every type — Amplitude's "Any Event". ${ZONE_NOTE}`,
    },
  ],
  allowedHosts: ["amplitude.com", "analytics.eu.amplitude.com"],
  // Beta until the numbers have been read back against a live project's own
  // charts. Every call here is shaped from Amplitude's documentation rather
  // than from a recorded response.
  status: "beta",
  minAppVersion: "0.1.0",
};
