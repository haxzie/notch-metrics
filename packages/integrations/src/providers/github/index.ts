import { z } from "zod";
import type { MetricId, ProviderManifest } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { EXPIRES_AT_FIELD, OAuthReauthRequiredError, type OAuthConfig } from "../../oauth.ts";
import type {
  AdapterContext,
  HttpResponse,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { ProviderError } from "../../types.ts";

/**
 * The repository a tile is about, asked for when the widget is configured.
 *
 * `pattern` is prevalidation only — the app greys out Done on a malformed
 * name, and `fetchMetric` checks it again, because a manifest is a hint and
 * the server is where it has to be true.
 */
const REPOSITORY_PARAM = {
  key: "repository",
  label: "Repository",
  type: "string",
  required: true,
  placeholder: "owner/name",
  help: "Which repository this tile counts.",
  pattern: "^[\\w.-]+/[\\w.-]+$",
} as const;

/**
 * Which branch's runs a CI tile lists.
 *
 * Optional, and empty means every branch: a repository with one active branch
 * reads the same either way, and demanding a branch name before the tile can
 * show anything would make the common case the fiddly one.
 */
const BRANCH_PARAM = {
  key: "branch",
  label: "Branch",
  type: "string",
  required: false,
  placeholder: "main",
  help: "Leave empty for every branch.",
  // A ref can hold almost anything a path can, so this only rules out what
  // would change the request rather than the branch: a slash is legal in a
  // branch name and `feature/x` must stay askable.
  pattern: "^[^\\s?&#]+$",
} as const;

export const manifest: ProviderManifest = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "Stars, forks and open work, per repository.",
  docsUrl: "https://docs.github.com/en/rest/metrics",
  iconPath: "/connectors/github.svg",
  // The brand black. The catalogue renders the mark on a light tile rather
  // than white on this, which is how GitHub itself shows the logo.
  accentColor: "#181717",
  keywords: ["repo", "repository", "open source", "code", "issues"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read public repositories you can see", "Read your name and avatar"],
    // Authorising is the whole connection now. The repository moved onto the
    // widget, so one GitHub account serves a tile per repository instead of
    // needing a connection each — which also means the stars of a repo you
    // do not own no longer costs a second connection.
    requiresSelection: false,
  },
  fields: [],
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
      params: [REPOSITORY_PARAM],
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
      params: [REPOSITORY_PARAM],
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
      params: [REPOSITORY_PARAM],
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
      params: [REPOSITORY_PARAM],
    },
    {
      id: "ci_runs",
      label: "CI runs",
      shortLabel: "CI",
      // The rows are the widget. `value` is the count behind them, which is
      // what a tile too short for rows falls back to and what a threshold
      // notification would read.
      unit: "count",
      granularities: ["day"],
      // A feed of what just happened, like a payments list: the same ten runs
      // whatever the range says, so neither a chart nor a comparison applies.
      supportsSeries: false,
      supportsCompare: false,
      keywords: ["ci", "build", "actions", "workflow", "pipeline", "checks"],
      // A minute, against the fifteen a daily bucket would otherwise hold it
      // for. This is the one metric here that is read to decide whether to go
      // and look at something, so being a quarter of an hour behind defeats
      // it. The notch polls every five minutes, so this mostly means the poll
      // is never served a cached answer rather than four requests a minute.
      freshnessSeconds: 60,
      methodology:
        "The ten most recent GitHub Actions runs, newest first. Public repositories only — " +
        "this connection is not allowed to read private ones.",
      params: [REPOSITORY_PARAM, BRANCH_PARAM],
    },
    {
      id: "followers",
      label: "Followers",
      shortLabel: "Followers",
      unit: "count",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: false,
      keywords: ["github", "audience", "profile"],
      // No `params`: this one is about the account that authorised, not a
      // repository, which is the reason params are declared per metric
      // rather than per connector.
      methodology: "People following the GitHub account this connection signed in as.",
    },
  ],
  allowedHosts: ["api.github.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};

export const credentialSchema = z.object({
  access_token: z.string().min(8),
  // Both present only when the OAuth App has "expire user authorization
  // tokens" switched on. GitHub turns that on by default for new apps, and
  // the tokens it then issues still start with `gho_` — so nothing about the
  // token itself says whether it will stop working in eight hours.
  refresh_token: z.string().min(8).optional(),
  [EXPIRES_AT_FIELD]: z.string().regex(/^\d+$/).optional(),
  /**
   * Legacy. Connections made before the repository moved onto the widget
   * carry one here, and their widgets have no `repository` param to supply —
   * so `fetchMetric` still falls back to it. Nothing writes it any more.
   */
  repository: z
    .string()
    .regex(/^[\w.-]+\/[\w.-]+$/, "A repository looks like owner/name.")
    .optional(),
});
export type GitHubCredentials = z.infer<typeof credentialSchema>;

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
function errorFor(response: HttpResponse): ProviderError {
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
    return new ProviderError(
      "auth_failed",
      "That repository could not be read. Check the name, and that the token can see it.",
    );
  }
  return errorForStatus("api.github.com", response);
}

async function get<T>(ctx: AdapterContext, creds: GitHubCredentials, path: string): Promise<T> {
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

interface Repository {
  full_name: string;
  stargazers_count: number;
  forks_count: number;
  open_issues_count: number;
  private: boolean;
}

interface SearchResult {
  total_count: number;
}

interface Account {
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
function repositoryFor(creds: GitHubCredentials, request: MetricRequest): string {
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
function repoPath(repository: string): string {
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
async function searchCount(
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

/**
 * One GitHub Actions run, as much of it as a row needs.
 *
 * `display_title` is the commit's subject — or the title of the pull request
 * the run is for — which is what somebody scanning a list is actually looking
 * for. `name` is the workflow's, and several workflows run on one commit.
 */
interface WorkflowRun {
  id: number;
  name: string | null;
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

interface WorkflowRuns {
  workflow_runs: WorkflowRun[];
}

/** Ten rows, the same as a payments feed and for the same reason. */
const CI_RUNS_LIMIT = 10;

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
function runState(run: WorkflowRun): {
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
function branchFor(request: MetricRequest): string | null {
  const branch = (request.params.branch ?? "").trim();
  if (!branch) return null;
  if (/[\s?&#]/.test(branch)) {
    throw new ProviderError("unsupported", `"${branch}" is not a branch name.`);
  }
  return branch;
}

/** Every metric here is a count with no history, so they share one shape. */
function snapshot(ctx: AdapterContext, value: number, note?: string): RawSeries {
  return {
    unit: "count",
    currency: null,
    // One point, at now. GitHub exposes no history for any of these, and a
    // flat line invented from a single reading would look like data.
    points: [{ t: ctx.now(), v: value }],
    value,
    previousValue: null,
    asOf: ctx.now(),
    note,
  };
}

interface TokenResponse {
  access_token?: string;
  refresh_token?: string;
  /** Seconds. Present only when the app issues expiring tokens. */
  expires_in?: number;
  error?: string;
  error_description?: string;
}

function hasToken(body: TokenResponse): body is TokenResponse & { access_token: string } {
  return typeof body.access_token === "string" && body.access_token.length > 0;
}

/**
 * The token fields of a credential blob, from either the code exchange or a
 * refresh — the two responses have the same shape.
 */
function tokens(body: TokenResponse & { access_token: string }): {
  access_token: string;
  refresh_token?: string;
  expires_at?: string;
} {
  return {
    access_token: body.access_token,
    ...(body.refresh_token ? { refresh_token: body.refresh_token } : {}),
    ...(typeof body.expires_in === "number" && body.expires_in > 0
      ? { [EXPIRES_AT_FIELD]: String(Date.now() + body.expires_in * 1000) }
      : {}),
  };
}

/**
 * GitHub's OAuth leg.
 *
 * `exchangeCode` and the repository list call `fetch` directly rather than
 * `ctx.http`: both happen before any adapter context exists, and the hosts
 * they reach are fixed strings in this file rather than anything a provider
 * response can steer. The allowlist exists to stop a *redirect* carrying the
 * user's token somewhere else, which is why `redirect: "manual"` is still set
 * on both.
 */
const oauth: OAuthConfig<GitHubCredentials> = {
  // `public_repo`, not `repo`.
  //
  // An OAuth App has no read-only scope for private repositories — `repo` is
  // read *and write* on every repository the user can reach, and this server
  // would then hold a token that can push to all of them to show a star
  // count. Private repositories need a GitHub App, which is a different
  // build; until then this asks for what it can actually justify.
  scopes: ["public_repo", "read:user"],
  scopeSummary: ["Read public repositories you can see", "Read your name and avatar"],

  authorizationUrl({ clientId, redirectUri, state }) {
    const url = new URL("https://github.com/login/oauth/authorize");
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("redirect_uri", redirectUri);
    url.searchParams.set("scope", this.scopes.join(" "));
    url.searchParams.set("state", state);
    return url.toString();
  },

  async exchangeCode({ code, redirectUri, clientId, clientSecret }) {
    const response = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      redirect: "manual",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        redirect_uri: redirectUri,
      }),
    });

    // GitHub answers 200 with `{ error }` for a bad or reused code rather
    // than a 4xx, so the status alone proves nothing.
    const body = (await response.json()) as TokenResponse;
    if (!response.ok || !hasToken(body)) {
      throw new ProviderError(
        "auth_failed",
        body.error_description ?? "GitHub would not complete the sign-in.",
      );
    }

    // Nothing else to fill in: the grant is the whole connection, and which
    // repository a number comes from is settled per widget.
    return tokens(body);
  },

  // Eight hours is the token's whole life when expiry is on. An hour of lead
  // is generous on purpose: the cron is five-minutely and a Worker tick can
  // be skipped, and a refresh an hour early costs nothing — the old token
  // keeps working until the new one is issued. The floor keeps a bug from
  // looping on the token endpoint.
  refresh: { leadTimeMs: 60 * 60 * 1000, minIntervalMs: 5 * 60 * 1000 },

  /**
   * Trades the refresh token for a new pair.
   *
   * A connection made before expiry was switched on has no refresh token and
   * a token that never expires; null says there is nothing to do. Once a
   * refresh token has been used it is dead, which is why the new one is
   * stored in the same write as the new access token.
   */
  async refreshCredentials({ credentials, clientId, clientSecret }) {
    if (!credentials.refresh_token) return null;

    const response = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      redirect: "manual",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "refresh_token",
        refresh_token: credentials.refresh_token,
      }),
    });
    const body = (await response.json().catch(() => ({}))) as TokenResponse;

    // `bad_refresh_token` is GitHub's one unambiguous "start over": the
    // refresh token expired through six months of disuse, was already used,
    // or the user revoked the app. Anything else — a 5xx, a mangled body —
    // is a reason to try again on the next tick, not to make somebody
    // reconnect.
    if (body.error === "bad_refresh_token" || body.error === "invalid_grant") {
      throw new OAuthReauthRequiredError(
        "GitHub has stopped honouring this connection. Reconnect it to carry on.",
      );
    }
    if (!response.ok || !hasToken(body)) {
      throw new Error(`GitHub token refresh failed: ${body.error ?? response.status}`);
    }
    return { ...credentials, ...tokens(body) };
  },
};

export const github: ProviderAdapter<GitHubCredentials> = {
  manifest,
  credentialSchema,
  // Tokens are never typed in or accepted from a submission, and there is
  // nothing else in the blob to ask a human for.
  userInputFields: [],
  oauth,

  async verify(ctx, creds): Promise<VerifyResult> {
    // `/user` rather than a repository: the connection is the account now, and
    // there is no repository at this point to prove anything about. It also
    // names the connection something stable — a login does not change when a
    // tile is pointed somewhere else.
    const account = await get<Account>(ctx, creds, "/user");

    return {
      accountLabel: account.login,
      currency: null,
      availableMetrics: [
        "stars",
        "forks",
        "open_issues",
        "open_pull_requests",
        "ci_runs",
        "followers",
      ] as MetricId[],
    };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    // Account-level, so it is answered before a repository is demanded.
    if (request.metric === "followers") {
      const account = await get<Account>(ctx, creds, "/user");
      return snapshot(ctx, account.followers);
    }

    const repository = repositoryFor(creds, request);
    switch (request.metric) {
      case "stars": {
        const repo = await get<Repository>(ctx, creds, repoPath(repository));
        return snapshot(ctx, repo.stargazers_count);
      }
      case "forks": {
        const repo = await get<Repository>(ctx, creds, repoPath(repository));
        return snapshot(ctx, repo.forks_count);
      }
      case "open_issues":
        return snapshot(ctx, await searchCount(ctx, creds, repository, "is:issue"));
      case "open_pull_requests":
        return snapshot(ctx, await searchCount(ctx, creds, repository, "is:pr"));
      case "ci_runs": {
        const branch = branchFor(request);
        const body = await get<WorkflowRuns>(
          ctx,
          creds,
          `${repoPath(repository)}/actions/runs?per_page=${CI_RUNS_LIMIT}` +
            (branch ? `&branch=${encodeURIComponent(branch)}` : ""),
        );
        const runs = body.workflow_runs ?? [];
        const items = runs.slice(0, CI_RUNS_LIMIT).map((run) => {
          const { state, status } = runState(run);
          return {
            id: String(run.id),
            // When it last moved, not when it was queued: a run that has been
            // going for an hour should not read as an hour old the moment it
            // finishes.
            t: new Date(run.updated_at || run.created_at),
            label: run.display_title?.trim() || run.name?.trim() || `Run ${run.id}`,
            // The workflow, and the branch when the tile is not already
            // pinned to one — otherwise every row would repeat it.
            detail:
              [run.name?.trim(), branch ? null : run.head_branch?.trim()]
                .filter(Boolean)
                .join(" · ") || null,
            amount: null,
            currency: null,
            status,
            state,
          };
        });

        return {
          unit: "count",
          currency: null,
          points: [{ t: ctx.now(), v: items.length }],
          value: items.length,
          previousValue: null,
          asOf: ctx.now(),
          items,
          note:
            items.length === 0
              ? branch
                ? `No Actions runs on ${branch}.`
                : "No Actions runs on this repository."
              : undefined,
        };
      }
      default:
        throw new ProviderError("unsupported", `GitHub does not provide ${request.metric}.`);
    }
  },
};
