import { scalar } from "../define.ts";
import { repositoryFor, searchCount } from "../client.ts";
import { REPOSITORY_PARAM } from "../params.ts";

export const openIssues = scalar({
  id: "open_issues",
  linkTemplate: "https://github.com/{repository}/issues",
  label: "Open issues",
  shortLabel: "Issues",
  unit: "count",
  // GitHub counts pull requests as issues on the repository object, so this
  // has to be a search query rather than `open_issues_count` — that field
  // reads high and nobody can see why.
  freshnessSeconds: 120,
  methodology: "Open issues, excluding pull requests.",
  params: [REPOSITORY_PARAM],

  async fetch(ctx, creds, request) {
    const repository = repositoryFor(creds, request);
    return { value: await searchCount(ctx, creds, repository, "is:issue") };
  },
});

export const openPullRequests = scalar({
  id: "open_pull_requests",
  linkTemplate: "https://github.com/{repository}/pulls",
  label: "Open pull requests",
  shortLabel: "PRs",
  unit: "count",
  freshnessSeconds: 120,
  methodology: "Pull requests currently open.",
  params: [REPOSITORY_PARAM],

  async fetch(ctx, creds, request) {
    const repository = repositoryFor(creds, request);
    return { value: await searchCount(ctx, creds, repository, "is:pr") };
  },
});
