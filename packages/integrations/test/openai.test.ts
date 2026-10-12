import { describe, expect, it } from "vitest";
import { openai } from "../src/providers/openai/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = { admin_key: "sk-admin-0123456789abcdefghij" };

/** `stubContext` freezes now at 2026-10-05T12:00:00Z. */
const request = {
  metric: "tokens" as const,
  granularity: "day" as const,
  from: new Date("2026-09-05T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
  params: {},
};

function bucket(day: string, results: Record<string, number>[]) {
  return {
    start_time: Math.floor(new Date(`${day}T00:00:00Z`).getTime() / 1000),
    end_time: Math.floor(new Date(`${day}T00:00:00Z`).getTime() / 1000) + 86_400,
    results,
  };
}

const usageRow = (input: number, output: number, requests = 1) => ({
  input_tokens: input,
  output_tokens: output,
  num_model_requests: requests,
});

describe("openai", () => {
  it("keeps the token metrics when the cost report is refused outright", async () => {
    // An optional probe must not fail the whole connection: four working
    // metrics beat a connector that cannot be connected at all.
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
      "/organization/costs": { __status: 400 },
    });
    const result = await openai.verify(ctx, creds);
    expect(result.availableMetrics).toEqual([
      "tokens",
      "input_tokens",
      "output_tokens",
      "api_requests",
    ]);
  });

  it("names the admin key as the problem rather than the key", async () => {
    // A perfectly valid `sk-proj-` key gets this 401. "Rejected the
    // credentials" sends somebody off to mint another one of the same kind.
    const ctx = stubContext({ "/organization/usage/completions": { __status: 401 } });
    const error = await openai.verify(ctx, creds).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("auth_failed");
    expect((error as ProviderError).message).toContain("Admin key");
  });

  it("keeps the connection when only the cost report is out of reach", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
      "/organization/costs": { __status: 403 },
    });

    const result = await openai.verify(ctx, creds);
    expect(result.availableMetrics).toEqual([
      "tokens",
      "input_tokens",
      "output_tokens",
      "api_requests",
    ]);
    expect(result.availableMetrics).not.toContain("api_spend");
  });

  it("labels the connection with the organisation the cost report reports", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
      "/organization/costs": {
        data: [bucket("2026-10-04", [{ organization_id: "org-abc" } as never])],
        has_more: false,
        next_page: null,
      },
    });

    const result = await openai.verify(ctx, creds);
    expect(result.accountLabel).toBe("org-abc");
    expect(result.availableMetrics).toContain("api_spend");
  });

  it("totals input and output tokens over the window", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": {
        data: [
          bucket("2026-09-10", [usageRow(1_000, 500), usageRow(200, 100)]),
          bucket("2026-09-20", [usageRow(300, 50)]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await openai.fetchMetric(ctx, creds, request);
    expect(result.value).toBe(2_150);
    expect(result.unit).toBe("count");
    expect(result.currency).toBeNull();
    // Gap-filled: a sparkline drawn from two days would compress the month.
    expect(result.points.length).toBeGreaterThan(28);
    expect(scalar(result.points.find((p) => p.t.toISOString().startsWith("2026-09-10"))).v).toBe(
      1_800,
    );
  });

  it("splits the comparison window off by date rather than re-fetching it", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": {
        data: [
          // Before `from` — the comparison half of one contiguous walk.
          bucket("2026-08-20", [usageRow(100, 0)]),
          bucket("2026-09-10", [usageRow(400, 0)]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await openai.fetchMetric(ctx, creds, { ...request, metric: "input_tokens" });
    expect(result.value).toBe(400);
    expect(result.previousValue).toBe(100);
    // One walk, not two: the request covers both windows.
    expect(ctx.calls).toHaveLength(1);
  });

  it("drops the comparison before it drops the number", async () => {
    // 90 days plus its comparison window is 180 days of daily buckets — six
    // requests. The window alone is three, so the delta goes and the figure stays.
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
    });

    const result = await openai.fetchMetric(ctx, creds, {
      ...request,
      granularity: "week",
      from: new Date("2026-07-07T00:00:00Z"),
    });
    expect(result.previousValue).toBeNull();
    const start = scalar(new URL(scalar(ctx.calls[0])).searchParams.get("start_time"));
    expect(Number(start) * 1000).toBe(new Date("2026-07-07T00:00:00Z").getTime());
  });

  it("refuses a year rather than walking two dozen pages", async () => {
    const ctx = stubContext({});
    const error = await openai
      .fetchMetric(ctx, creds, {
        ...request,
        granularity: "month",
        from: new Date("2025-10-05T00:00:00Z"),
      })
      .catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("unsupported");
    // The walk is refused before it starts, not abandoned halfway through.
    expect(ctx.calls).toHaveLength(0);
  });

  it("stops paging at the cap even when the provider keeps offering more", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": {
        data: [bucket("2026-09-10", [usageRow(1, 1)])],
        has_more: true,
        next_page: "page_next",
      },
    });

    await openai.fetchMetric(ctx, creds, request);
    expect(ctx.calls).toHaveLength(4);
  });

  it("reads spend in minor units and never as a float", async () => {
    const ctx = stubContext({
      "/organization/costs": {
        data: [
          bucket("2026-09-10", [{ amount: { value: 12.345, currency: "usd" } } as never]),
          bucket("2026-09-11", [{ amount: { value: 0.005, currency: "usd" } } as never]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await openai.fetchMetric(ctx, creds, { ...request, metric: "api_spend" });
    expect(result.unit).toBe("currency");
    expect(result.currency).toBe("USD");
    // 1234.5 + 0.5 cents, rounded once at the end.
    expect(result.value).toBe(1_235);
    expect(Number.isInteger(result.value)).toBe(true);
    expect(result.points.every((p) => Number.isInteger(p.v))).toBe(true);
  });

  it("excludes a non-USD charge rather than summing it at 1:1", async () => {
    const ctx = stubContext({
      "/organization/costs": {
        data: [
          bucket("2026-09-10", [
            { amount: { value: 10, currency: "usd" } } as never,
            { amount: { value: 90, currency: "eur" } } as never,
          ]),
        ],
        has_more: false,
        next_page: null,
      },
    });

    const result = await openai.fetchMetric(ctx, creds, { ...request, metric: "api_spend" });
    expect(result.value).toBe(1_000);
    expect(result.note).toContain("EUR");
  });

  it("says why an hourly spend series is not on offer", async () => {
    const ctx = stubContext({});
    const error = await openai
      .fetchMetric(ctx, creds, { ...request, metric: "api_spend", granularity: "hour" })
      .catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("unsupported");
    expect((error as ProviderError).message).toContain("once a day");
  });

  it("scopes every call to the project when one is configured", async () => {
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
    });

    await openai.fetchMetric(ctx, { ...creds, project_id: "proj_42" }, request);
    expect(scalar(ctx.calls[0])).toContain("project_ids%5B%5D=proj_42");
  });
});

describe("openai verify", () => {
  it("does not hide spend over a transient failure", async () => {
    // `availableMetrics` is written once, at connect. Narrowing on a 503 would
    // grey out the spend metric until the user reconnected.
    const ctx = stubContext({
      "/organization/usage/completions": { data: [], has_more: false, next_page: null },
      "/organization/costs": { __status: 503 },
    });

    const error = await openai.verify(ctx, creds).catch((e: unknown) => e);
    expect((error as ProviderError).code).toBe("provider_down");
  });
});
