import { provider } from "../../metric.ts";
import { get, type Account } from "./client.ts";
import { credentialSchema } from "./define.ts";
import { manifest } from "./manifest.ts";
import { oauth } from "./oauth.ts";
import { ciRuns } from "./metrics/ci-runs.ts";
import { followers } from "./metrics/followers.ts";
import { forks } from "./metrics/forks.ts";
import { openIssues, openPullRequests } from "./metrics/open-issues.ts";
import { stars } from "./metrics/stars.ts";

export { credentialSchema, type GitHubCredentials } from "./define.ts";
export { manifest } from "./manifest.ts";

export const github = provider({
  manifest,
  credentialSchema,
  // Tokens are never typed in or accepted from a submission, and there is
  // nothing else in the blob to ask a human for.
  userInputFields: [],
  oauth,

  // Declaration order is the order the widget browser lists them in.
  metrics: [stars, forks, openIssues, openPullRequests, ciRuns, followers],

  async verify(ctx, creds) {
    // `/user` rather than a repository: the connection is the account now, and
    // there is no repository at this point to prove anything about. It also
    // names the connection something stable — a login does not change when a
    // tile is pointed somewhere else.
    const account = await get<Account>(ctx, creds, "/user");

    // No `availableMetrics`: the ids were written out here as a copy of the
    // six above, and a seventh metric added without being copied in was
    // unreachable with nothing to fail. `provider()` derives them.
    return { accountLabel: account.login, currency: null };
  },
});
