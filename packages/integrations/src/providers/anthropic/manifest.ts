import type { ProviderManifest } from "@notch/schemas";

/**
 * Named for the product people recognise rather than the company, because the
 * tile sits next to "OpenAI" and "Moonshot AI" and has twelve characters to
 * say which one it is.
 */
export const manifest: Omit<ProviderManifest, "metrics"> = {
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
  setupSteps: [
    {
      text: "Open the Claude Console, then Settings, then Admin keys.",
      url: "https://platform.claude.com/docs/en/manage-claude/admin-api-keys",
    },
    { text: "Create an admin key. A workspace key cannot read usage." },
    { text: "Copy the key, then paste it above." },
    { text: "Leave Workspace ID empty to total the whole organisation." },
  ],
  allowedHosts: ["api.anthropic.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
