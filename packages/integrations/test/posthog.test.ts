import { describe, expect, it } from "vitest";
import { posthog } from "../src/providers/posthog/index.ts";
import { ProviderError } from "../src/types.ts";
import { scalar, stubContext } from "./helpers.ts";

const creds = {
  api_key: "phx_abcdefghijklmnopqrstuvwxyz0123456789",
  project_id: "4521",
  region: "us" as const,
};

const identity = {
  team: { id: 4521, name: "Website" },
  organization: { name: "Acme" },
};

const request = {
  metric: "pageviews" as const,
  granularity: "day" as const,
  from: new Date("2026-10-01T00:00:00Z"),
  to: new Date("2026-10-05T00:00:00Z"),
  comparePrevious: true,
  wantSeries: true,
  params: {},
};

/** Epoch seconds of a day in October 2026, which is what the bucket column is. */
function day(n: number): number {
  return Math.floor(new Date(`2026-10-0${n}T00:00:00Z`).getTime() / 1000);
}

/** `stubContext` matches on the URL only, so the SQL is captured separately. */
function contextFor(reply: (sql: string) => unknown[][], overrides: Record<string, unknown> = {}) {
  const sent: string[] = [];
  const ctx = stubContext({
    "/api/users/@me/": identity,
    "/api/projects/4521/query/": { results: [] },
    ...overrides,
  });
  const inner = ctx.http.bind(ctx);
  ctx.http = async (url: string, init?: RequestInit) => {
    if (init?.body) {
      const body = JSON.parse(String(init.body)) as { query: { query: string } };
      sent.push(body.query.query);
      return {
        ok: true,
        status: 200,
        headers: new Headers(),
        json: <T>() => Promise.resolve({ results: reply(body.query.query) } as T),
        text: () => Promise.resolve(""),
      };
    }
    return inner(url, init);
  };
  return { ctx, sent };
}

describe("posthog additive metrics", () => {
  it("asks for both windows in one query and splits them at `from`", async () => {
    const { ctx, sent } = contextFor(() => [
      [day(1) - 86_400 * 2, 10], // inside the compare window
      [day(1), 40],
      [day(3), 60],
    ]);

    const series = await posthog.fetchMetric(ctx, creds, request);

    // One widened range, not two round trips.
    expect(sent).toHaveLength(1);
    const sql = scalar(sent[0]);
    expect(sql).toContain("toStartOfDay(timestamp)");
    expect(sql).toContain("event = '$pageview'");
    // 2026-09-27, four days before `from`, because the window is four days.
    expect(sql).toContain(`timestamp >= toDateTime(${day(1) - 86_400 * 4})`);
    expect(sql).toContain(`timestamp < toDateTime(${day(5)})`);

    expect(series.value).toBe(100);
    expect(series.previousValue).toBe(10);
    expect(series.unit).toBe("count");
    expect(series.currency).toBeNull();
  });

  it("gap-fills the quiet days rather than drawing a step", async () => {
    const { ctx } = contextFor(() => [
      [day(1), 40],
      [day(4), 60],
    ]);
    const series = await posthog.fetchMetric(ctx, creds, { ...request, comparePrevious: false });
    // Oct 1 to Oct 5 inclusive, with Oct 2, 3 and 5 at zero.
    expect(series.points.map((p) => p.v)).toEqual([40, 0, 0, 60, 0]);
  });

  it("does not report a delta nobody asked for", async () => {
    // A row from before the window is returned anyway; without the flag
    // gating it, it would quietly become a comparison.
    const { ctx, sent } = contextFor(() => [
      [day(1) - 86_400, 99],
      [day(1), 5],
    ]);
    const series = await posthog.fetchMetric(ctx, creds, { ...request, comparePrevious: false });
    expect(series.previousValue).toBeNull();
    // And the range is not widened when there is nothing to compare against.
    expect(scalar(sent[0])).toContain(`timestamp >= toDateTime(${day(1)})`);
  });

  it("buckets by the hour when asked for one", async () => {
    const { ctx, sent } = contextFor(() => []);
    await posthog.fetchMetric(ctx, creds, { ...request, granularity: "hour" });
    expect(scalar(sent[0])).toContain("toStartOfHour(timestamp)");
  });

  it("counts new users out of persons, by when the profile was created", async () => {
    const { ctx, sent } = contextFor(() => [[day(2), 7]]);
    const series = await posthog.fetchMetric(ctx, creds, { ...request, metric: "new_users" });
    const sql = scalar(sent[0]);
    expect(sql).toContain("FROM persons");
    expect(sql).toContain("toStartOfDay(created_at)");
    expect(series.value).toBe(7);
  });
});

describe("posthog de-duplicated metrics", () => {
  it("takes the headline from a window total, not the sum of its own chart", async () => {
    // One person active on three days is three bars and one user. Summing
    // the buckets would report three.
    const { ctx, sent } = contextFor((sql) =>
      sql.includes("is_current")
        ? [
            [1, 1],
            [0, 4],
          ]
        : [
            [day(1), 1],
            [day(2), 1],
            [day(3), 1],
          ],
    );

    const series = await posthog.fetchMetric(ctx, creds, { ...request, metric: "active_users" });

    expect(sent).toHaveLength(2);
    expect(scalar(sent[0])).toContain("count(DISTINCT person_id)");
    expect(series.points.map((p) => p.v)).toEqual([1, 1, 1, 0, 0]);
    expect(series.value).toBe(1);
    expect(series.previousValue).toBe(4);
  });

  it("does not pay for the totals query when the metric is additive", async () => {
    const { ctx, sent } = contextFor(() => [[day(1), 3]]);
    await posthog.fetchMetric(ctx, creds, { ...request, metric: "events" });
    expect(sent).toHaveLength(1);
  });

  it("counts sessions by id, ignoring events that carry none", async () => {
    const { ctx, sent } = contextFor((sql) => (sql.includes("is_current") ? [[1, 12]] : []));
    const series = await posthog.fetchMetric(ctx, creds, { ...request, metric: "sessions" });
    expect(scalar(sent[0])).toContain("count(DISTINCT properties.$session_id)");
    expect(scalar(sent[0])).toContain("properties.$session_id IS NOT NULL");
    expect(series.value).toBe(12);
  });

  it("reads a previous window of zero as zero, not as absent", async () => {
    // Only the current row comes back when the compare window is empty.
    const { ctx } = contextFor((sql) => (sql.includes("is_current") ? [[1, 9]] : []));
    const series = await posthog.fetchMetric(ctx, creds, { ...request, metric: "active_users" });
    expect(series.previousValue).toBe(0);
  });
});

describe("posthog project resolution", () => {
  it("uses the typed project id without asking who the key belongs to", async () => {
    const { ctx } = contextFor(() => []);
    await posthog.fetchMetric(ctx, creds, request);
    expect(ctx.calls.some((url) => url.includes("/api/users/@me/"))).toBe(false);
  });

  it("falls back to the key's own project when the field is blank", async () => {
    const { ctx, sent } = contextFor(() => []);
    await posthog.fetchMetric(ctx, { ...creds, project_id: "" }, request);
    expect(ctx.calls.some((url) => url.includes("/api/users/@me/"))).toBe(true);
    expect(sent).toHaveLength(1);
  });

  it("reaches the EU host when the region says so", async () => {
    const ctx = stubContext({ "/api/users/@me/": identity });
    await posthog.verify(ctx, { ...creds, project_id: "", region: "eu" }).catch(() => undefined);
    expect(scalar(ctx.calls[0])).toContain("https://eu.posthog.com/");
  });
});

describe("posthog verify", () => {
  it("names the connection by organization and project", async () => {
    const { ctx } = contextFor(() => [[1]]);
    const result = await posthog.verify(ctx, creds);
    expect(result.accountLabel).toBe("Acme — Website");
    expect(result.availableMetrics).toContain("pageviews");
    expect(result.currency).toBeNull();
  });

  it("does not repeat the organization when the project shares its name", async () => {
    const { ctx } = contextFor(() => [[1]], {
      "/api/users/@me/": { team: { id: 4521, name: "Acme" }, organization: { name: "Acme" } },
    });
    expect((await posthog.verify(ctx, creds)).accountLabel).toBe("Acme");
  });

  it("proves the key can query without reading any events", async () => {
    const { ctx, sent } = contextFor(() => [[1]]);
    await posthog.verify(ctx, creds);
    expect(scalar(sent[0])).toBe("SELECT 1");
  });

  it("blames the scope rather than the key when the query is refused", async () => {
    const ctx = stubContext({
      "/api/users/@me/": identity,
      "/api/projects/4521/query/": { __status: 403 },
    });
    await expect(posthog.verify(ctx, creds)).rejects.toThrow(/Query Read scope/);
  });

  it("names the region on a 401, because the other region answers 401 too", async () => {
    const ctx = stubContext({ "/api/users/@me/": { __status: 401 } });
    const error = await posthog.verify(ctx, creds).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect((error as ProviderError).code).toBe("auth_failed");
    expect((error as ProviderError).message).toContain("US");
  });

  it("asks for a project id when the key has no default one", async () => {
    const ctx = stubContext({ "/api/users/@me/": { organization: { name: "Acme" } } });
    await expect(posthog.verify(ctx, { ...creds, project_id: "" })).rejects.toThrow(
      /Enter a project ID/,
    );
  });
});

describe("posthog unsupported metrics", () => {
  it("refuses a metric it has no query for", async () => {
    const { ctx } = contextFor(() => []);
    await expect(posthog.fetchMetric(ctx, creds, { ...request, metric: "mrr" })).rejects.toThrow(
      /does not provide mrr/,
    );
  });
});
