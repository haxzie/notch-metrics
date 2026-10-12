import { describe, expect, it } from "vitest";
import { anthropic } from "../src/providers/anthropic/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { admin_key: "sk-ant-admin01-0123456789abcdef" };

const request = {
  metric: "tokens" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
  params: {},
};

function bucket(day: string, results: unknown[]) {
  return {
    starting_at: `${day}T00:00:00Z`,
    ending_at: `${day}T23:59:59Z`,
    results,
  };
}

const usageRow = (options: {
  uncached?: number;
  cacheRead?: number;
  write5m?: number;
  write1h?: number;
  output?: number;
}) => ({
  uncached_input_tokens: options.uncached ?? 0,
  cache_read_input_tokens: options.cacheRead ?? 0,
  cache_creation: {
    ephemeral_5m_input_tokens: options.write5m ?? 0,
    ephemeral_1h_input_tokens: options.write1h ?? 0,
  },
  output_tokens: options.output ?? 0,
});

describe("anthropic", () => {
  it("names all three things a 401 can mean", async () => {
    const ctx = stubContext({ "/organizations/usage_report/messages": { __status: 401 } });
    const error = await anthropic.verify(ctx, creds).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("auth_failed");
    expect((error as ProviderError).message).toMatch(/Admin key/);
    expect((error as ProviderError).message).toMatch(/workspace/i);
  });

  /**
   * The bug that made the connector unconnectable, and the reason no fixture
   * caught it: every other test here stubs by path and asserts the parsing,
   * so the query string the adapter actually builds was never looked at.
   *
   * The cost report snaps `starting_at` up to the next UTC day and defaults
   * `ending_at` to the start of today. `now - 24h` therefore snaps to exactly
   * that default for all but the midnight hour, and the API answers 400
   * "ending date must be after starting date" — which surfaced as a connect
   * failure that read like a rejected key.
   */
  it("asks the cost report for a range that is a whole bucket", async () => {
    const ctx = stubContext({
      "/organizations/usage_report/messages": { data: [], has_more: false, next_page: null },
      "/organizations/cost_report": { data: [], has_more: false, next_page: null },
    });
    await anthropic.verify(ctx, creds);

    const cost = ctx.calls.find((url) => url.includes("/organizations/cost_report"));
    const startingAt = new URL(scalar(cost)).searchParams.get("starting_at") ?? "";

    // Midnight UTC, and strictly before today — `ending_at` defaults to the
    // start of today, and the two being equal is the 400.
    expect(startingAt).toMatch(/T00:00:00\.000Z$/);
    expect(new Date(startingAt).getTime()).toBeLessThan(
      Date.UTC(2026, 9, 5), // ctx.now() is 2026-10-05T12:00Z
    );
  });

  it("floors the spend window so the first day is not snapped away", async () => {
    const ctx = stubContext({
      "/organizations/cost_report": { data: [], has_more: false, next_page: null },
    });
    await anthropic.fetchMetric(ctx, creds, {
      ...request,
      metric: "api_spend",
      // Deliberately mid-afternoon: passed through, this whole day is lost.
      from: new Date("2026-09-20T15:30:00.000Z"),
      to: new Date("2026-10-05T12:00:00.000Z"),
    });

    const cost = ctx.calls.find((url) => url.includes("/organizations/cost_report"));
    const startingAt = new URL(scalar(cost)).searchParams.get("starting_at") ?? "";
    expect(startingAt).toMatch(/T00:00:00\.000Z$/);
  });

  it("keeps the token metrics when the cost report is refused outright", async () => {
    // A 400 from an optional probe used to fail the whole connection.
    const ctx = stubContext({
      "/organizations/usage_report/messages": { data: [], has_more: false, next_page: null },
      "/organizations/cost_report": { __status: 400 },
    });
    const result = await anthropic.verify(ctx, creds);
    expect(result.availableMetrics).toEqual(["tokens", "input_tokens", "output_tokens"]);
  });

  it("offers no request count, because the usage report has none", async () => {
    const ctx = stubContext({
      "/organizations/usage_report/messages": { data: [], has_more: false, next_page: null },
      "/organizations/cost_report": { data: [], has_more: false, next_page: null },
    });

    const result = await anthropic.verify(ctx, creds);
    expect(result.availableMetrics).toEqual([
      "tokens",
      "input_tokens",
      "output_tokens",
      "api_spend",
    ]);
    expect(result.availableMetrics).not.toContain("api_requests");
  });

  it("counts cache reads and cache writes as input tokens", async () => {
    // The trap: a cache-heavy workload reads most of its context rather than
    // sending it, so `uncached_input_tokens` alone is a fraction of the volume.
    const ctx = stubContext({
      "/organizations/usage_report/messages": {
        data: [
          bucket("2026-09-10", [
            usageRow({ uncached: 1_000, cacheRead: 9_000, write5m: 400, write1h: 100 }),
          ]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const input = await anthropic.fetchMetric(ctx, creds, { ...request, metric: "input_tokens" });
    expect(input.value).toBe(10_500);
  });

  it("tolerates a bucket with no cache_creation block", async () => {
    const ctx = stubContext({
      "/organizations/usage_report/messages": {
        data: [
          bucket("2026-09-10", [
            { uncached_input_tokens: 7, cache_read_input_tokens: 3, output_tokens: 2 },
          ]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await anthropic.fetchMetric(ctx, creds, request);
    expect(result.value).toBe(12);
  });

  it("reads the cost amount as cents, not as dollars", async () => {
    // `"123.78912"` is $1.2379. Read as dollars it is a hundred times the bill
    // and still looks like a plausible number.
    const ctx = stubContext({
      "/organizations/cost_report": {
        data: [
          bucket("2026-09-10", [{ amount: "123.78912", currency: "USD", workspace_id: null }]),
          bucket("2026-09-11", [{ amount: "0.4", currency: "USD", workspace_id: null }]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await anthropic.fetchMetric(ctx, creds, { ...request, metric: "api_spend" });
    expect(result.currency).toBe("USD");
    expect(result.value).toBe(124);
    expect(Number.isInteger(result.value)).toBe(true);
  });

  it("rejects a cost amount that is not a number rather than totalling NaN", async () => {
    const ctx = stubContext({
      "/organizations/cost_report": {
        data: [bucket("2026-09-10", [{ amount: "n/a", currency: "USD", workspace_id: null }])],
        has_more: false,
        next_page: null,
      },
    });

    const error = await anthropic
      .fetchMetric(ctx, creds, { ...request, metric: "api_spend" })
      .catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("bad_response");
  });

  it("scopes a workspace's cost by grouping, since the report has no filter", async () => {
    const ctx = stubContext({
      "/organizations/cost_report": {
        data: [
          bucket("2026-09-10", [
            { amount: "500", currency: "USD", workspace_id: "wrkspc_mine" },
            { amount: "9000", currency: "USD", workspace_id: "wrkspc_theirs" },
          ]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await anthropic.fetchMetric(
      ctx,
      { ...creds, workspace_id: "wrkspc_mine" },
      { ...request, metric: "api_spend" },
    );

    // Without the grouping every row comes back `workspace_id: null` and a
    // scoped connection quietly reports the whole organisation's bill.
    expect(scalar(ctx.calls[0])).toContain("group_by%5B%5D=workspace_id");
    expect(result.value).toBe(500);
  });

  it("scopes usage with the filter the usage report does have", async () => {
    const ctx = stubContext({
      "/organizations/usage_report/messages": { data: [], has_more: false, next_page: null },
    });

    await anthropic.fetchMetric(ctx, { ...creds, workspace_id: "wrkspc_mine" }, request);
    expect(scalar(ctx.calls[0])).toContain("workspace_ids%5B%5D=wrkspc_mine");
  });

  it("refuses a year rather than walking two dozen pages", async () => {
    const ctx = stubContext({});
    const error = await anthropic
      .fetchMetric(ctx, creds, {
        ...request,
        granularity: "month",
        from: new Date("2025-10-05T00:00:00Z"),
      })
      .catch((e: unknown) => e);

    expect((error as ProviderError).code).toBe("unsupported");
    expect(ctx.calls).toHaveLength(0);
  });

  it("asks for hourly buckets only when the widget wants an hourly series", async () => {
    const ctx = stubContext({
      "/organizations/usage_report/messages": { data: [], has_more: false, next_page: null },
    });

    await anthropic.fetchMetric(ctx, creds, {
      ...request,
      granularity: "hour",
      from: new Date("2026-10-04T12:00:00Z"),
    });
    expect(scalar(ctx.calls[0])).toContain("bucket_width=1h");
  });
});
