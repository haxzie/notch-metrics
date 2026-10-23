import { scalar } from "../define.ts";
import { get, repoPath, repositoryFor, type Repository } from "../client.ts";
import { REPOSITORY_PARAM } from "../params.ts";

export const stars = scalar({
  id: "stars",
  linkTemplate: "https://github.com/{repository}/stargazers",
  label: "Stars",
  shortLabel: "Stars",
  unit: "count",
  // A snapshot, not a total. GitHub's API reports the current count and
  // offers no history, so a series would have to be invented. Declared by
  // the factory rather than by two booleans, so there is no `granularities`
  // here to promise a range nothing can answer.
  freshnessSeconds: 120,
  methodology: "Stargazers on the repository right now.",
  params: [REPOSITORY_PARAM],

  async fetch(ctx, creds, request) {
    const repo = await get<Repository>(ctx, creds, repoPath(repositoryFor(creds, request)));
    return { value: repo.stargazers_count };
  },
});
