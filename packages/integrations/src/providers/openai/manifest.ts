import type { ProviderManifest } from "@notch/schemas";

/**
 * Both usage endpoints are organisation-scoped and daily-bucketed, so every
 * metric here shares one shape: a token or request count per day, totalled
 * over the window.
 */
export const manifest: ProviderManifest = {
  id: "openai",
  name: "OpenAI",
  category: "ai",
  tagline: "Token usage and spend across your OpenAI organisation.",
  docsUrl: "https://platform.openai.com/settings/organization/admin-keys",
  iconPath: "/connectors/openai.svg",
  accentColor: "#000000",
  keywords: ["llm", "ai", "gpt", "chatgpt", "inference", "api"],
  authMode: "api_key",
  fields: [
    {
      key: "admin_key",
      label: "Admin key",
      type: "secret",
      required: true,
      placeholder: "sk-admin-…",
      // Spelled out because the failure is otherwise indistinguishable from a
      // typo: the usage endpoints answer 401 to an ordinary `sk-proj-` key,
      // which reads as "wrong key" rather than "wrong kind of key".
      help: "Settings → Organization → Admin keys. A project or user key cannot read usage and will be rejected.",
      pattern: "^sk-",
    },
    {
      key: "project_id",
      label: "Project ID",
      type: "string",
      required: false,
      placeholder: "proj_…",
      help: "Leave empty to total every project in the organisation.",
    },
  ],
  metrics: [
    {
      id: "tokens",
      label: "Tokens",
      shortLabel: "Tokens",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Input plus output tokens on chat and completions requests in the window. Input includes cached reads and cache writes, so this matches what the Usage page totals rather than what you were charged for.",
    },
    {
      id: "input_tokens",
      label: "Input tokens",
      shortLabel: "Input",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Input tokens on completions requests, cached reads and cache writes included. Audio and image inputs are counted in their own token units, as OpenAI reports them.",
    },
    {
      id: "output_tokens",
      label: "Output tokens",
      shortLabel: "Output",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      methodology: "Output tokens generated on completions requests in the window.",
    },
    {
      id: "api_requests",
      label: "API requests",
      shortLabel: "Requests",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Model requests on the completions endpoint. One batch job counts as the requests inside it, not as one.",
    },
    {
      id: "api_spend",
      label: "API spend",
      shortLabel: "Spend",
      unit: "currency",
      // No `hour`. OpenAI's cost endpoint buckets by day and nothing finer, so
      // an hourly series would be one day's figure repeated or stacked on a
      // single midnight point — both of which read as data.
      granularities: ["day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      methodology:
        "Billed cost per day from OpenAI's cost report, every line item included — tokens, tools and storage. Rounded to the cent per day, so it tracks the invoice rather than the fractional amounts the API returns.",
    },
  ],
  allowedHosts: ["api.openai.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
