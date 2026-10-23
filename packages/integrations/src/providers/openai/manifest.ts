import type { ProviderManifest } from "@notch/schemas";

/**
 * Both usage endpoints are organisation-scoped and daily-bucketed, so every
 * metric here shares one shape: a token or request count per day, totalled
 * over the window.
 */
export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "openai",
  name: "OpenAI",
  category: "ai",
  tagline: "Token usage and spend across your OpenAI organisation.",
  docsUrl: "https://platform.openai.com/settings/organization/admin-keys",
  dashboardUrl: "https://platform.openai.com/usage",
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
  allowedHosts: ["api.openai.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
