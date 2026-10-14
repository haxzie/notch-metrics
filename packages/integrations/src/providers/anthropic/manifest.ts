import type { ProviderManifest } from "@notch/schemas";

/**
 * Named for the product people recognise rather than the company, because the
 * tile sits next to "OpenAI" and "Moonshot AI" and has twelve characters to
 * say which one it is.
 */
export const manifest: ProviderManifest = {
  id: "anthropic",
  name: "Claude",
  category: "ai",
  tagline: "Token usage and spend across your Claude organisation.",
  docsUrl: "https://platform.claude.com/docs/en/manage-claude/admin-api-keys",
  dashboardUrl: "https://console.anthropic.com",
  iconPath: "/connectors/anthropic.svg",
  accentColor: "#D97757",
  keywords: ["llm", "ai", "claude", "anthropic", "inference", "api"],
  authMode: "api_key",
  fields: [
    {
      key: "admin_key",
      label: "Admin key",
      type: "secret",
      required: true,
      placeholder: "sk-ant-admin01-…",
      // The Admin API is unavailable to individual accounts entirely, which is
      // a different failure from a bad key and worth saying before somebody
      // spends an afternoon regenerating keys that were never going to work.
      help: "Console → Settings → Admin keys. Workspace-scoped keys cannot read usage, and individual accounts have no Admin API.",
      pattern: "^sk-ant-",
    },
    {
      key: "workspace_id",
      label: "Workspace ID",
      type: "string",
      required: false,
      placeholder: "wrkspc_…",
      help: "Leave empty to total every workspace in the organisation.",
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
      freshnessSeconds: 300,
      methodology:
        "Input plus output tokens on Messages requests in the window. Input is uncached input, cache reads and cache writes added together, which is what the Usage page shows. It is not what you were billed, since cache reads cost a tenth of the rest.",
    },
    {
      id: "input_tokens",
      label: "Input tokens",
      shortLabel: "Input",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 300,
      methodology:
        "Uncached input, cache reads and both cache-write tiers added together. Each is priced differently; this is the volume, not the bill.",
    },
    {
      id: "output_tokens",
      label: "Output tokens",
      shortLabel: "Output",
      unit: "count",
      granularities: ["hour", "day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 300,
      methodology:
        "Output tokens generated on Messages requests in the window. Thinking tokens are output tokens and are counted here.",
    },
    {
      id: "api_spend",
      label: "API spend",
      shortLabel: "Spend",
      unit: "currency",
      // The cost report is daily-only, same as OpenAI's.
      granularities: ["day", "week"],
      supportsSeries: true,
      supportsCompare: true,
      freshnessSeconds: 300,
      methodology:
        "Billed cost per day from the cost report: tokens, web search and code execution. Priority Tier is billed differently and is not included, which is Anthropic's own caveat, not ours.",
    },
  ],
  allowedHosts: ["api.anthropic.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
