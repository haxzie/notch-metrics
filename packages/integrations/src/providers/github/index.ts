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

export const manifest: ProviderManifest = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "Stars, forks and open work from a repository.",
  docsUrl: "https://docs.github.com/en/rest/metrics",
  iconPath: "/providers/github.svg",
  // The brand black. The catalogue renders the mark on a light tile rather
  // than white on this, which is how GitHub itself shows the logo.
  accentColor: "#181717",
  keywords: ["repo", "repository", "open source", "code", "issues"],
  authMode: "oauth2",
  oauth: {
    scopeSummary: ["Read public repositories you can see", "Read your name and avatar"],
    // The repository is chosen from a list after authorising rather than
    // typed. A name typed before the grant exists cannot be checked against
    // what the grant actually covers, so the first sign of a typo would be a
    // widget that never fills in.
    requiresSelection: true,
    selectionLabel: "Repository",
  },
  fields: [
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
  repository: z.string().regex(/^[\w.-]+\/[\w.-]+$/, "A repository looks like owner/name."),
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
  qualifier: "is:issue" | "is:pr",
): Promise<number> {
  const query = encodeURIComponent(`repo:${creds.repository} ${qualifier} is:open`);
  // `per_page=1` because only `total_count` is read; the page itself is
  // thrown away and a default page of 30 issue bodies is not free.
  const body = await get<SearchResult>(ctx, creds, `/search/issues?q=${query}&per_page=1`);
  return body.total_count;
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

    // `repository` is filled in by the selection below; the schema is parsed
    // once, at the end of the flow, when both halves exist.
    return { ...tokens(body), repository: "" };
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

  selection: {
    label: "Repository",
    field: "repository",
    async options(credentials) {
      // Sorted by last push, which puts the repository somebody just came
      // from at the top. 100 is one page: a chooser is not a backup of
      // somebody's account, and the list is searchable in the page.
      const response = await fetch(
        "https://api.github.com/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member",
        {
          redirect: "manual",
          headers: {
            authorization: `Bearer ${credentials.access_token}`,
            accept: "application/vnd.github+json",
            "x-github-api-version": "2022-11-28",
            "user-agent": "notch-metrics",
          },
        },
      );
      if (!response.ok) {
        throw new ProviderError("auth_failed", "We could not list your repositories.");
      }

      const repos = (await response.json()) as {
        full_name: string;
        description: string | null;
        stargazers_count: number;
        private: boolean;
      }[];

      return repos.map((repo) => ({
        value: repo.full_name,
        label: repo.full_name,
        // The star count, because two forks of the same project are
        // otherwise told apart only by the owner prefix.
        hint: repo.private ? "Private" : `${repo.stargazers_count} stars`,
      }));
    },
  },
};

export const github: ProviderAdapter<GitHubCredentials> = {
  manifest,
  credentialSchema,
  // The access token lives in the same blob as the repository and must never
  // be rendered as a form field or accepted from a submission. The
  // repository is not typed either — it is chosen from the list above.
  userInputFields: [],
  oauth,

  async verify(ctx, creds): Promise<VerifyResult> {
    // The repository, not `/user`: it proves the token works *and* that it
    // can see this repository, which is the thing every metric needs.
    const repo = await get<Repository>(ctx, creds, `/repos/${creds.repository}`);

    const available: MetricId[] = ["stars", "forks", "open_issues", "open_pull_requests"];

    return {
      // The repository is what distinguishes two GitHub connections, so it is
      // the detail `connectionName` puts after the provider.
      accountLabel: repo.full_name,
      currency: null,
      availableMetrics: available,
    };
  },

  async fetchMetric(ctx, creds, request: MetricRequest): Promise<RawSeries> {
    switch (request.metric) {
      case "stars": {
        const repo = await get<Repository>(ctx, creds, `/repos/${creds.repository}`);
        return snapshot(ctx, repo.stargazers_count);
      }
      case "forks": {
        const repo = await get<Repository>(ctx, creds, `/repos/${creds.repository}`);
        return snapshot(ctx, repo.forks_count);
      }
      case "open_issues":
        return snapshot(ctx, await searchCount(ctx, creds, "is:issue"));
      case "open_pull_requests":
        return snapshot(ctx, await searchCount(ctx, creds, "is:pr"));
      default:
        throw new ProviderError("unsupported", `GitHub does not provide ${request.metric}.`);
    }
  },
};
