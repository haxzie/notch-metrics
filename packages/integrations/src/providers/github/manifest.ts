import type { ProviderManifest } from "@notch/schemas";

/**
 * Everything about the connector that is not a metric.
 *
 * `metrics` is absent on purpose — `provider()` derives it from the metric
 * definitions, so a descriptor and the code that answers it cannot drift,
 * and a metric cannot be added to one without the other.
 */
export const manifest: Omit<ProviderManifest, "metrics"> = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "Stars, forks and open work, per repository.",
  docsUrl: "https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api",
  // The token page rather than the dashboard: every reason to follow this
  // link is a token that needs making, revoking or widening.
  dashboardUrl: "https://github.com/settings/tokens",
  iconPath: "/connectors/github.svg",
  // The brand black. The catalogue renders the mark on a light tile rather
  // than white on this, which is how GitHub itself shows the logo.
  accentColor: "#181717",
  keywords: ["repo", "repository", "open source", "code", "issues"],
  authMode: "api_key",
  fields: [
    {
      key: "access_token",
      label: "Personal access token",
      type: "secret",
      required: true,
      placeholder: "github_pat_… or ghp_…",
      help: "Settings → Developer settings → Personal access tokens. Read access is enough.",
      // Both families, because both work and people have whichever they
      // already made. Not `gho_`: a connection made under the old OAuth flow
      // still holds one and keeps working, but nobody can type one in.
      pattern: "^(ghp_|github_pat_)[A-Za-z0-9_]+$",
    },
  ],
  // One repository is not named here. The repository lives on the widget, so
  // one token serves a tile per repository, including repositories the
  // account does not own.
  setupSteps: [
    {
      text: "Open Settings, then Developer settings.",
      url: "https://github.com/settings/tokens",
    },
    { text: "Select Personal access tokens, then Tokens (classic)." },
    { text: "Tick repo for private repositories, or public_repo for public ones." },
    { text: "Tick read:user, which names the connection after your account." },
    { text: "Generate the token, then paste it above." },
    {
      text: "A fine-grained token works too, with Metadata, Issues, Pull requests and Actions set to read.",
    },
  ],
  allowedHosts: ["api.github.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};
