import { scalar } from "../define.ts";
import { get, repoPath, repositoryFor, type Repository } from "../client.ts";
import { REPOSITORY_PARAM } from "../params.ts";

export const forks = scalar({
  id: "forks",
  linkTemplate: "https://github.com/{repository}/forks",
  label: "Forks",
  shortLabel: "Forks",
  unit: "count",
  freshnessSeconds: 300,
  methodology: "Forks of the repository right now.",
  params: [REPOSITORY_PARAM],

  async fetch(ctx, creds, request) {
    const repo = await get<Repository>(ctx, creds, repoPath(repositoryFor(creds, request)));
    return { value: repo.forks_count };
  },
});
