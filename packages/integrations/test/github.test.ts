import { describe, expect, it } from "vitest";
import { github } from "../src/providers/github/index.ts";
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
