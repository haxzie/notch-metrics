import { scalar } from "../define.ts";
import { get, type Account } from "../client.ts";

export const followers = scalar({
  id: "followers",
  label: "Followers",
  shortLabel: "Followers",
  unit: "count",
  keywords: ["github", "audience", "profile"],
  // No `params`: this one is about the account that authorised, not a
  // repository, which is the reason params are declared per metric rather
  // than per connector. It is also why it never calls `repositoryFor` — the
  // switch answered this case before demanding a repository, and a separate
  // file cannot forget to.
  freshnessSeconds: 300,
  methodology: "People following the GitHub account this connection signed in as.",

  async fetch(ctx, creds) {
    const account = await get<Account>(ctx, creds, "/user");
    return { value: account.followers };
  },
});
