import { afterEach, describe, expect, it, vi } from "vitest";
import { github } from "../src/providers/github/index.ts";
import { OAuthReauthRequiredError } from "../src/oauth.ts";
import { ProviderError } from "../src/types.ts";
import { stubContext } from "./helpers.ts";

const creds = { access_token: "gho_11ABCDEFGHIJKLMNOP" };
/** A connection made before the repository moved onto the widget. */
const legacyCreds = { ...creds, repository: "haxzie/notch-metrics" };
const account = { login: "haxzie", followers: 128 };

const request = {
  metric: "stars" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
  params: { repository: "haxzie/notch-metrics" },
};

const repo = {
  full_name: "haxzie/notch-metrics",
  stargazers_count: 412,
  forks_count: 37,
  // Deliberately the sum of open issues *and* open PRs, which is what GitHub
  // puts here and what the issue count must not be taken from.
  open_issues_count: 23,
  private: false,
};

/**
 * One of each outcome a tile has to draw, plus one GitHub has not invented
 * yet — `stale` stands in for whatever it adds next.
 */
const runs = {
  total_count: 5,
  workflow_runs: [
    {
      id: 101,
      name: "CI",
      display_title: "Tell people when something happened, in the notch",
      head_branch: "main",
      event: "push",
      status: "completed",
      conclusion: "success",
      created_at: "2026-10-05T11:00:00Z",
      updated_at: "2026-10-05T11:04:00Z",
    },
    {
      id: 102,
      name: "CI",
      display_title: "Build the Mac app on the toolchain CI actually has",
      head_branch: "main",
      event: "push",
      status: "completed",
      conclusion: "failure",
      created_at: "2026-10-05T10:00:00Z",
      updated_at: "2026-10-05T10:06:00Z",
    },
    {
      id: 103,
      name: "Release",
      display_title: "Cut 0.2.1",
      head_branch: "main",
      event: "workflow_dispatch",
      status: "in_progress",
      conclusion: null,
      created_at: "2026-10-05T09:00:00Z",
      updated_at: "2026-10-05T09:01:00Z",
    },
    {
      id: 104,
      name: "CI",
      display_title: "Search the Integrations list",
      head_branch: "haxzie/search",
      event: "pull_request",
      status: "completed",
      conclusion: "cancelled",
      created_at: "2026-10-05T08:00:00Z",
      updated_at: "2026-10-05T08:02:00Z",
    },
    {
      id: 105,
      name: "CI",
      display_title: null,
      head_branch: "main",
      event: "push",
      status: "completed",
      conclusion: "stale",
      created_at: "2026-10-05T07:00:00Z",
      updated_at: "2026-10-05T07:03:00Z",
    },
  ],
};

describe("github", () => {
  it("names the connection after the account, not a repository", async () => {
    // One connection per GitHub account now, so the label has to be stable
    // when a tile is pointed at a different repository.
    const ctx = stubContext({ "/user": account });
    const result = await github.verify(ctx, creds);
    expect(result.accountLabel).toBe("haxzie");
    expect(result.currency).toBeNull();
    expect(result.availableMetrics).toEqual(
      expect.arrayContaining(["stars", "open_pull_requests", "followers"]),
    );
  });

  it("takes the repository from the widget, not the connection", async () => {
    const ctx = stubContext({ "/repos/": repo });
    await github.fetchMetric(ctx, creds, { ...request, params: { repository: "vercel/next.js" } });
    expect(ctx.calls[0]).toContain("/repos/vercel/next.js");
  });

  it("asks a different repository per widget on one connection", async () => {
    // The whole point of the move: two tiles, one connection, two repos.
    const ctx = stubContext({ "/repos/": repo });
    await github.fetchMetric(ctx, creds, { ...request, params: { repository: "a/one" } });
    await github.fetchMetric(ctx, creds, { ...request, params: { repository: "b/two" } });
    expect(ctx.calls[0]).toContain("/repos/a/one");
    expect(ctx.calls[1]).toContain("/repos/b/two");
  });

  it("falls back to a pre-existing connection's repository", async () => {
    // Widgets made before this change carry no param. Without the fallback
    // every one of them would blank on the deploy that shipped it.
    const ctx = stubContext({ "/repos/": repo });
    const series = await github.fetchMetric(ctx, legacyCreds, { ...request, params: {} });
    expect(ctx.calls[0]).toContain("/repos/haxzie/notch-metrics");
    expect(series.value).toBe(412);
  });

  it("says which widget needs attention when no repository is set", async () => {
    const ctx = stubContext({});
    const error = await github
      .fetchMetric(ctx, creds, { ...request, params: {} })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
    expect((error as ProviderError).message).toMatch(/Pick a repository/);
  });

  it("rejects a repository that is not owner/name rather than building a URL from it", async () => {
    const ctx = stubContext({});
    const error = await github
      .fetchMetric(ctx, creds, { ...request, params: { repository: "../../user" } })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
    expect(ctx.calls).toHaveLength(0);
  });

  it("reads followers from the account, with no repository at all", async () => {
    const ctx = stubContext({ "/user": account });
    const series = await github.fetchMetric(ctx, creds, {
      ...request,
      metric: "followers",
      params: {},
    });
    expect(series.value).toBe(128);
    expect(ctx.calls[0]).toContain("/user");
  });

  it("declares the repository on the metrics that need one, and not on followers", async () => {
    const byId = Object.fromEntries(github.manifest.metrics.map((m) => [m.id, m]));
    expect(byId.stars?.params?.[0]?.key).toBe("repository");
    expect(byId.followers?.params ?? []).toEqual([]);
  });

  it("reads stars and forks from the repository", async () => {
    const ctx = stubContext({ "/repos/haxzie/notch-metrics": repo });
    const stars = await github.fetchMetric(ctx, creds, request);
    const forks = await github.fetchMetric(ctx, creds, { ...request, metric: "forks" });
    expect(stars.value).toBe(412);
    expect(forks.value).toBe(37);
    // No history exists for either, so one point and no comparison.
    expect(stars.points).toHaveLength(1);
    expect(stars.previousValue).toBeNull();
  });

  it("counts open issues without the pull requests", async () => {
    // The repository object would say 23. Only 15 of those are issues.
    const ctx = stubContext({
      "is%3Aissue": { total_count: 15 },
      "is%3Apr": { total_count: 8 },
    });

    const issues = await github.fetchMetric(ctx, creds, { ...request, metric: "open_issues" });
    const prs = await github.fetchMetric(ctx, creds, {
      ...request,
      metric: "open_pull_requests",
    });

    expect(issues.value).toBe(15);
    expect(prs.value).toBe(8);
    expect(ctx.calls.every((url) => url.includes("per_page=1"))).toBe(true);
  });

  it("lists CI runs newest first, with a state a tile can draw", async () => {
    const ctx = stubContext({ "/actions/runs": runs });
    const series = await github.fetchMetric(ctx, creds, { ...request, metric: "ci_runs" });

    expect(series.items?.map((item) => item.state)).toEqual([
      "succeeded",
      "failed",
      "running",
      // Cancelled, and a conclusion that does not exist yet. Both grey rather
      // than either of them reading as a failure.
      "neutral",
      "neutral",
    ]);
    // The provider's own word is kept beside it: the tooltip says `cancelled`,
    // not "neutral".
    expect(series.items?.[3]?.status).toBe("cancelled");
    expect(series.value).toBe(5);
  });

  it("titles a row with the workflow, because one push starts several", async () => {
    // Labelled by the commit, the first two rows here are the same sentence
    // at nearly the same age — which reads as a tile that failed to load.
    const ctx = stubContext({ "/actions/runs": runs });
    const series = await github.fetchMetric(ctx, creds, { ...request, metric: "ci_runs" });
    expect(series.items?.map((i) => i.label)).toEqual(["CI", "CI", "Release", "CI", "CI"]);
    // The commit is still there for a tile wide enough to show it.
    expect(series.items?.[0]?.detail).toBe(
      "Tell people when something happened, in the notch · main",
    );
  });

  it("dates a row by when the run last moved, not when it was queued", async () => {
    // A run that has been going an hour must not read as an hour old the
    // moment it goes green.
    const ctx = stubContext({ "/actions/runs": runs });
    const series = await github.fetchMetric(ctx, creds, { ...request, metric: "ci_runs" });
    expect(series.items?.[0]?.t.toISOString()).toBe("2026-10-05T11:04:00.000Z");
  });

  it("asks GitHub for one branch when the widget names one", async () => {
    const ctx = stubContext({ "/actions/runs": runs });
    await github.fetchMetric(ctx, creds, {
      ...request,
      metric: "ci_runs",
      params: { repository: "haxzie/notch-metrics", branch: "feature/thing" },
    });
    expect(ctx.calls[0]).toContain("branch=feature%2Fthing");
  });

  it("lists every branch when the widget names none", async () => {
    const ctx = stubContext({ "/actions/runs": runs });
    await github.fetchMetric(ctx, creds, {
      ...request,
      metric: "ci_runs",
      params: { repository: "haxzie/notch-metrics" },
    });
    expect(ctx.calls[0]).not.toContain("branch=");
    // Without a branch filter the rows have to say which branch they are on.
    const series = await github.fetchMetric(ctx, creds, { ...request, metric: "ci_runs" });
    expect(series.items?.[3]?.detail).toBe("Search the Integrations list · haxzie/search");
  });

  it("refuses a branch that would add query parameters of its own", async () => {
    const ctx = stubContext({ "/actions/runs": runs });
    const error = await github
      .fetchMetric(ctx, creds, {
        ...request,
        metric: "ci_runs",
        params: { repository: "haxzie/notch-metrics", branch: "main&per_page=100" },
      })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
    expect(ctx.calls).toHaveLength(0);
  });

  it("says so rather than showing an empty tile when there are no runs", async () => {
    const ctx = stubContext({ "/actions/runs": { total_count: 0, workflow_runs: [] } });
    const series = await github.fetchMetric(ctx, creds, {
      ...request,
      metric: "ci_runs",
      params: { repository: "haxzie/notch-metrics", branch: "main" },
    });
    expect(series.items).toEqual([]);
    expect(series.note).toContain("main");
  });

  it("holds a CI feed for a minute, not for the daily bucket's fifteen", async () => {
    // The whole point of the widget is being current. The server reads this.
    const ci = github.manifest.metrics.find((m) => m.id === "ci_runs");
    expect(ci?.freshnessSeconds).toBe(60);
    expect(ci?.params?.map((p) => p.key)).toEqual(["repository", "branch"]);
    expect(ci?.params?.find((p) => p.key === "branch")?.required).toBe(false);
  });

  it("treats a spent quota as rate limiting, not as a bad token", async () => {
    // GitHub sends 403 for both. Read as auth_failed it would mark the
    // integration broken and stop polling until the user reconnected.
    const reset = Math.floor(Date.now() / 1000) + 120;
    const ctx = stubContext({
      "/user": {
        __status: 403,
        __headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": String(reset) },
      },
    });

    const error = await github.verify(ctx, creds).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("rate_limited");
    expect((error as ProviderError).retryAfterSeconds).toBeGreaterThan(100);
  });

  it("still reports a 403 with quota left as a credentials problem", async () => {
    const ctx = stubContext({
      "/user": { __status: 403, __headers: { "x-ratelimit-remaining": "4999" } },
    });
    const error = await github.verify(ctx, creds).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("auth_failed");
  });

  it("explains a 404 as a repository it cannot read", async () => {
    const ctx = stubContext({ "/repos/": { __status: 404 } });
    const error = await github.fetchMetric(ctx, creds, request).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("auth_failed");
    expect((error as ProviderError).message).toMatch(/token can see it/);
  });

  it("refuses a metric it does not provide", async () => {
    const ctx = stubContext({});
    const error = await github
      .fetchMetric(ctx, creds, { ...request, metric: "mrr" })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("unsupported");
  });
});

/** GitHub's token endpoint answering with `body`, and recording what was asked. */
function stubTokenEndpoint(body: Record<string, unknown>, status = 200) {
  const calls: Record<string, unknown>[] = [];
  vi.stubGlobal("fetch", async (_url: string, init?: RequestInit) => {
    calls.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return new Response(JSON.stringify(body), { status });
  });
  return calls;
}

const client = { clientId: "Iv1.client", clientSecret: "secret" };

describe("github oauth tokens", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("keeps the refresh token and expiry when GitHub issues expiring tokens", async () => {
    stubTokenEndpoint({ access_token: "gho_new", refresh_token: "ghr_new", expires_in: 28800 });
    const before = Date.now();
    const creds = await github.oauth!.exchangeCode({
      code: "c",
      redirectUri: "https://api/callback",
      ...client,
    });
    expect(creds.access_token).toBe("gho_new");
    expect(creds.refresh_token).toBe("ghr_new");
    // Eight hours out, give or take the test's own clock.
    expect(Number(creds.expires_at)).toBeGreaterThanOrEqual(before + 28800 * 1000);
    expect(Number(creds.expires_at)).toBeLessThan(before + 28800 * 1000 + 5_000);
  });

  it("stores no expiry for a token that does not expire", async () => {
    stubTokenEndpoint({ access_token: "gho_forever" });
    const creds = await github.oauth!.exchangeCode({
      code: "c",
      redirectUri: "https://api/callback",
      ...client,
    });
    expect(creds.refresh_token).toBeUndefined();
    expect(creds.expires_at).toBeUndefined();
  });

  it("has nothing to refresh without a refresh token", async () => {
    const calls = stubTokenEndpoint({});
    const result = await github.oauth!.refreshCredentials({ credentials: creds, ...client });
    expect(result).toBeNull();
    expect(calls).toHaveLength(0);
  });

  it("trades the refresh token for a new pair", async () => {
    const calls = stubTokenEndpoint({
      access_token: "gho_second",
      refresh_token: "ghr_second",
      expires_in: 28800,
    });
    const result = await github.oauth!.refreshCredentials({
      credentials: { ...creds, refresh_token: "ghr_first", expires_at: "1" },
      ...client,
    });
    expect(calls[0]).toMatchObject({ grant_type: "refresh_token", refresh_token: "ghr_first" });
    expect(result).toMatchObject({ access_token: "gho_second", refresh_token: "ghr_second" });
    expect(Number(result?.expires_at)).toBeGreaterThan(Date.now());
  });

  it("asks for a human when the refresh token is dead", async () => {
    // GitHub answers 200 with an error body, so the status proves nothing.
    stubTokenEndpoint({ error: "bad_refresh_token" });
    await expect(
      github.oauth!.refreshCredentials({
        credentials: { ...creds, refresh_token: "ghr_used" },
        ...client,
      }),
    ).rejects.toBeInstanceOf(OAuthReauthRequiredError);
  });

  it("treats anything else as a reason to try again later", async () => {
    stubTokenEndpoint({}, 502);
    await expect(
      github.oauth!.refreshCredentials({
        credentials: { ...creds, refresh_token: "ghr_x" },
        ...client,
      }),
    ).rejects.not.toBeInstanceOf(OAuthReauthRequiredError);
  });
});
