import { afterEach, describe, expect, it, vi } from "vitest";
import { github } from "../src/providers/github/index.ts";
import { OAuthReauthRequiredError } from "../src/oauth.ts";
import { ProviderError } from "../src/types.ts";
import { stubContext } from "./helpers.ts";

const creds = { access_token: "gho_11ABCDEFGHIJKLMNOP", repository: "haxzie/notch-metrics" };

const request = {
  metric: "stars" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: false,
  wantSeries: true,
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

describe("github", () => {
  it("names the connection after the repository", async () => {
    const ctx = stubContext({ "/repos/haxzie/notch-metrics": repo });
    const result = await github.verify(ctx, creds);
    expect(result.accountLabel).toBe("haxzie/notch-metrics");
    expect(result.currency).toBeNull();
    expect(result.availableMetrics).toContain("open_pull_requests");
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

  it("treats a spent quota as rate limiting, not as a bad token", async () => {
    // GitHub sends 403 for both. Read as auth_failed it would mark the
    // integration broken and stop polling until the user reconnected.
    const reset = Math.floor(Date.now() / 1000) + 120;
    const ctx = stubContext({
      "/repos/": {
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
      "/repos/": { __status: 403, __headers: { "x-ratelimit-remaining": "4999" } },
    });
    const error = await github.verify(ctx, creds).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("auth_failed");
  });

  it("explains a 404 as a repository it cannot read", async () => {
    const ctx = stubContext({ "/repos/": { __status: 404 } });
    const error = await github.verify(ctx, creds).catch((e: unknown) => e);
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

  it("trades the refresh token for a new pair and keeps the repository", async () => {
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
    expect(result).toMatchObject({
      access_token: "gho_second",
      refresh_token: "ghr_second",
      repository: "haxzie/notch-metrics",
    });
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
