import { errorForStatus } from "../../http.ts";
import type { AdapterContext, HttpResponse, MetricRequest } from "../../types.ts";
import { ProviderError } from "../../types.ts";
import type { GitHubCredentials } from "./define.ts";

const API = "https://api.github.com";

/**
 * GitHub answers 403 — not 429 — when a quota is spent.
 *
 * Left to `errorForStatus` that becomes `auth_failed`, which marks the
 * integration broken and stops polling it entirely. A user whose token is
 * fine would have to reconnect to recover from being briefly over quota.
 *
 * The two cases are told apart by the headers: the primary limit leaves
 * `x-ratelimit-remaining: 0` and a reset timestamp, and a secondary limit
 * sends `retry-after`.
 */
export function errorFor(response: HttpResponse): ProviderError {
  if (response.status === 403 || response.status === 429) {
    const retryAfter = Number(response.headers.get("retry-after"));
    if (Number.isFinite(retryAfter) && retryAfter > 0) {
      return new ProviderError("rate_limited", "GitHub asked us to wait", retryAfter);
    }
    if (response.headers.get("x-ratelimit-remaining") === "0") {
      const reset = Number(response.headers.get("x-ratelimit-reset"));
      const seconds = Number.isFinite(reset)
        ? Math.max(1, Math.ceil(reset - Date.now() / 1000))
        : 60;
      return new ProviderError("rate_limited", "GitHub's rate limit is spent", seconds);
    }
  }
  if (response.status === 404) {
    // A repository that does not exist and one the token cannot see are the
    // same 404 — GitHub will not confirm a private repository to a caller
    // without access. The message has to cover both, because we cannot tell.
    //
    // With `repo` the usual cause is no longer visibility but reach: a
    // repository in an organisation that has not approved this OAuth app,
    // or one the signed-in account is simply not a member of.
    //
    // Except for one case worth naming outright. A connection made before
    // this connector asked for `repo` still holds a `public_repo` token, and
    // it keeps working for public repositories, so nothing announces that it
    // is the reason a private one 404s. GitHub returns the granted scopes on
    // every response, so the token can say so itself rather than leaving
    // somebody to re-check a repository name that was right all along.
    const granted = response.headers.get("x-oauth-scopes") ?? "";
    if (granted !== "" && !granted.split(/,\s*/).includes("repo")) {
      return new ProviderError(
        "unsupported",
        "Reconnect GitHub to read private repositories. This connection was " +
          "authorised for public ones only.",
      );
    }
    //
    // `unsupported`, not `auth_failed`. This is a statement about one
    // widget's repository, not about the connection: the same token is
    // answering for every other tile in the notch. Calling it an auth
    // failure marked the whole integration broken and asked the user to
    // reconnect, which cannot fix a repository that was renamed — and it
    // locked the row out of token refresh on the way past.
    return new ProviderError(
      "unsupported",
      "That repository could not be read. Check the name, and that this account can see it.",
    );
  }
  return errorForStatus("api.github.com", response);
}

export async function get<T>(
  ctx: AdapterContext,
  creds: GitHubCredentials,
  path: string,
): Promise<T> {
  const response = await ctx.http(`${API}${path}`, {
    headers: {
      authorization: `Bearer ${creds.access_token}`,
      accept: "application/vnd.github+json",
      // Pinned, so a future default on GitHub's side cannot change a field
      // under an installed app that has no way to be updated for it.
      "x-github-api-version": "2022-11-28",
      // Mandatory. Without it GitHub answers 403 for every request, which
      // reads exactly like a bad token.
      "user-agent": "notch-metrics",
    },
  });
  if (!response.ok) throw errorFor(response);
  return response.json<T>();
}

export interface Repository {
  full_name: string;
  stargazers_count: number;
  forks_count: number;
  open_issues_count: number;
  private: boolean;
}

export interface SearchResult {
  total_count: number;
}

export interface Account {
  login: string;
  followers: number;
}

/**
 * Which repository this request is about.
 *
 * The widget's own parameter, falling back to the connection's for anything
 * made before the repository moved off the connection. Without that fallback
 * every GitHub tile in an existing notch would blank on the deploy that
 * shipped this.
 */
export function repositoryFor(creds: GitHubCredentials, request: MetricRequest): string {
  const repository = (request.params.repository ?? creds.repository ?? "").trim();
  if (!repository) {
    throw new ProviderError("unsupported", "Pick a repository for this widget.");
  }
  // Re-checked here rather than trusted from the manifest's `pattern`: that
  // is a hint the app renders, and this value reaches a request path.
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) {
    throw new ProviderError("unsupported", `"${repository}" is not an owner/name repository.`);
  }
  return repository;
}

/** Each segment encoded separately, so the slash between them survives. */
export function repoPath(repository: string): string {
  const [owner = "", name = ""] = repository.split("/");
  return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;
}

/**
 * Counted through search rather than by subtracting from
 * `open_issues_count`.
 *
 * That field is issues *and* pull requests, so "open issues" taken from it
 * reads high by exactly the number of open PRs — the single most common way
 * to get this number wrong, and invisible until somebody counts by hand.
 */
export async function searchCount(
  ctx: AdapterContext,
  creds: GitHubCredentials,
  repository: string,
  qualifier: "is:issue" | "is:pr",
): Promise<number> {
  const query = encodeURIComponent(`repo:${repository} ${qualifier} is:open`);
  // `per_page=1` because only `total_count` is read; the page itself is
  // thrown away and a default page of 30 issue bodies is not free.
  const body = await get<SearchResult>(ctx, creds, `/search/issues?q=${query}&per_page=1`);
  return body.total_count;
}

/** One GitHub Actions run, as much of it as a row needs. */
export interface WorkflowRun {
  id: number;
  /** The workflow's name — "CI", "Deploy the API". */
  name: string | null;
  /** The commit's subject, or the title of the PR the run is for. */
  display_title: string | null;
  head_branch: string | null;
  event: string | null;
  /** `queued`, `in_progress`, `completed`, and others GitHub may add. */
  status: string | null;
  /** Null until `status` is `completed`. */
  conclusion: string | null;
  created_at: string;
  updated_at: string;
}

export interface WorkflowRuns {
  workflow_runs: WorkflowRun[];
}

/** Ten rows, the same as a payments feed and for the same reason. */
export const CI_RUNS_LIMIT = 10;

/**
 * GitHub's nine conclusions and six statuses, collapsed to the four states a
 * tile can draw.
 *
 * Done here rather than in the app: these are GitHub's words, GitHub adds to
 * them, and an installed app matching on them would need a release every time
 * it did. `action_required` is a failure on purpose — it is a run that has
 * stopped and is waiting for a human, which is the same thing to anyone
 * glancing at a notch.
 */
export function runState(run: WorkflowRun): {
  state: "succeeded" | "failed" | "running" | "neutral";
  status: string;
} {
  const status = (run.conclusion ?? run.status ?? "unknown").toLowerCase();
  switch (status) {
    case "success":
      return { state: "succeeded", status };
    case "failure":
    case "timed_out":
    case "startup_failure":
    case "action_required":
      return { state: "failed", status };
    case "queued":
    case "in_progress":
    case "requested":
    case "waiting":
    case "pending":
      return { state: "running", status };
    // `cancelled`, `skipped`, `neutral`, `stale` — and anything GitHub adds
    // later, which is grey rather than wrong.
    default:
      return { state: "neutral", status };
  }
}

/**
 * The branch filter for a CI tile, or nothing.
 *
 * Validated here as well as by the manifest's `pattern`, because this reaches
 * a query string: a value carrying its own `&` would otherwise append
 * parameters to GitHub's request rather than name a branch.
 */
export function branchFor(request: MetricRequest): string | null {
  const branch = (request.params.branch ?? "").trim();
  if (!branch) return null;
  if (/[\s?&#]/.test(branch)) {
    throw new ProviderError("unsupported", `"${branch}" is not a branch name.`);
  }
  return branch;
}
