import type { ProviderManifest } from "@notch/schemas";

export const manifest: ProviderManifest = {
  id: "posthog",
  name: "PostHog",
  category: "analytics",
  tagline: "Product analytics — users, events and conversion from PostHog.",
  docsUrl: "https://posthog.com/docs/api/personal-api-keys",
  iconPath: "/providers/posthog.svg",
  // The dark surface their full-colour mark is drawn against; the orange
  // is one of the colours *in* the mark, not a backdrop for it.
  accentColor: "#1D1D1D",
  keywords: ["product analytics", "events", "funnels", "sessions"],
  authMode: "api_key",
  fields: [
    {
      key: "api_key",
      label: "Personal API key",
      type: "secret",
      required: true,
      placeholder: "phx_…",
      help: "Settings → Personal API keys. Needs the Query Read and User Read scopes.",
    },
    {
      key: "project_id",
      label: "Project ID",
      type: "string",
      // Optional on purpose. A numeric id nobody knows by heart is the field
      // people abandon the form on, and the key already names a default
      // project — see `resolveProject`.
      required: false,
      placeholder: "Leave blank for your default project",
      help: "The number in your PostHog project URL. Blank uses the key's current project.",
    },
    {
      key: "region",
      label: "Region",
      type: "select",
      required: true,
      // The two regions are separate databases, so a US key is simply not
      // found in the EU one. That answers 401 — the same thing a revoked key
      // answers, which is why this is asked rather than probed.
      help: "PostHog Cloud US or EU. The wrong one returns 401, exactly like a bad key.",
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
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "People with at least one event in the window, de-duplicated. The headline counts each person once across the whole window, so the bars do not add up to it — one person on three days is one user and three bars. Days are your PostHog project's timezone, so the figures match its own dashboards.",
    },
    {
      id: "new_users",
      label: "New users",
      shortLabel: "New",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Person profiles PostHog first created in the window. Anonymous visitors who are never identified do not create one, so this counts people PostHog can tell apart rather than every first visit.",
    },
    {
      id: "events",
      label: "Events",
      shortLabel: "Events",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Every event recorded in the window, of every name.",
    },
    {
      id: "pageviews",
      label: "Pageviews",
      shortLabel: "Views",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "`$pageview` events in the window. Repeat views by one person all count.",
    },
    {
      id: "sessions",
      label: "Sessions",
      shortLabel: "Sessions",
      unit: "count",
      granularities: ["hour", "day", "week", "month"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Distinct `$session_id`s seen in the window. The headline de-duplicates across the whole window, so a session spanning midnight is one session and two bars.",
    },
  ],
  // The private API hosts, not the `*.i.posthog.com` ingestion ones — those
  // are POST-only capture endpoints and answer nothing we ask for.
  allowedHosts: ["us.posthog.com", "eu.posthog.com"],
  // Beta until the numbers have been read back against a live project's own
  // dashboards. Every call here is shaped from PostHog's documentation
  // rather than from a recorded response.
  status: "beta",
  minAppVersion: "0.1.0",
};
