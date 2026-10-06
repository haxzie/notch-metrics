import { z } from "zod";
import type { ProviderManifest } from "@notch/schemas";
import type { ProviderAdapter } from "../../types.ts";
import { notImplemented } from "../../types.ts";

export const manifest: ProviderManifest = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "Stars, forks and open work from a repository.",
  docsUrl: "https://github.com/settings/tokens",
  iconPath: "/providers/github.svg",
  // The brand black. The catalogue renders the mark on a light tile rather
  // than white on this, which is how GitHub itself shows the logo.
  accentColor: "#181717",
  keywords: ["repo", "repository", "open source", "code", "issues"],
  authMode: "api_key",
  fields: [
    {
      key: "token",
      label: "Personal access token",
      type: "secret",
      required: true,
      help: "A fine-grained token with read-only Contents and Metadata on the repository is enough. A classic token needs `public_repo` at most.",
    },
    {
      key: "repository",
      label: "Repository",
      type: "string",
      required: true,
      placeholder: "owner/name",
      help: "The repository these numbers come from.",
    },
  ],
  metrics: [
    {
      id: "stars",
      label: "Stars",
      shortLabel: "Stars",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      // A snapshot, not a total. GitHub's API reports the current count and
      // offers no history, so a series would have to be invented.
      methodology: "Stargazers on the repository right now.",
    },
    {
      id: "forks",
      label: "Forks",
      shortLabel: "Forks",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Forks of the repository right now.",
    },
    {
      id: "open_issues",
      label: "Open issues",
      shortLabel: "Issues",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      // GitHub counts pull requests as issues on the repository object, so
      // this has to be a search query rather than `open_issues_count` — that
      // field reads high and nobody can see why.
      methodology: "Open issues, excluding pull requests.",
    },
    {
      id: "open_pull_requests",
      label: "Open pull requests",
      shortLabel: "PRs",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      methodology: "Pull requests currently open.",
    },
  ],
  allowedHosts: ["api.github.com"],
  status: "coming_soon",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  token: z.string().min(8),
  repository: z.string().regex(/^[\w.-]+\/[\w.-]+$/, "A repository looks like owner/name."),
});
export type GitHubCredentials = z.infer<typeof credentialSchema>;

/**
 * Declared but not implemented. `status: "coming_soon"` is what the
 * catalogue reads to list it and disable its connect button; returning
 * zeroes instead would look like a working integration reporting a dead
 * repository.
 */
export const github: ProviderAdapter<GitHubCredentials> = {
  manifest,
  credentialSchema,
  async verify() {
    notImplemented("GitHub");
  },
  async fetchMetric() {
    notImplemented("GitHub");
  },
};
