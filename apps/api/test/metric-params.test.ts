import { describe, expect, it } from "vitest";
import { MetricQuery, Widget } from "@notch/schemas";
import { cacheKey } from "../src/lib/metrics.ts";

const base = {
  integrationId: "int_1",
  metric: "stars" as const,
  range: "30d" as const,
  series: true,
};

describe("per-widget metric params", () => {
  /**
   * The failure this guards against is silent. One GitHub connection now
   * serves a tile per repository, so two widgets differing only by
   * `repository` would share a cache entry and serve each other's star count
   * — a believable number, attached to the wrong repo, with nothing in the
   * UI to suggest anything went wrong.
   */
  it("gives two repositories on one connection different cache keys", () => {
    const a = cacheKey({ ...base, params: { repository: "owner/a" } }, "day");
    const b = cacheKey({ ...base, params: { repository: "owner/b" } }, "day");
    expect(a).not.toBe(b);
  });

  it("gives the same widget the same key whatever order the params arrive in", () => {
    const a = cacheKey({ ...base, params: { repository: "owner/a", branch: "main" } }, "day");
    const b = cacheKey({ ...base, params: { branch: "main", repository: "owner/a" } }, "day");
    expect(a).toBe(b);
  });

  it("leaves a param-less key byte-identical to the one already deployed", () => {
    // Not cosmetic, and not a detail the shape of the key makes obvious: every
    // cached metric in the estate is stored under the old form. A separator
    // appended unconditionally — even a bare trailing colon — orphans all of
    // them on deploy, and every notch goes to its provider at once to refill.
    expect(cacheKey({ ...base, metric: "mrr", params: {} }, "day")).toBe("int_1:mrr:day:30d");
    expect(cacheKey({ ...base, metric: "mrr", params: undefined as never }, "day")).toBe(
      "int_1:mrr:day:30d",
    );
  });

  it("extends the key only for a widget that actually carries parameters", () => {
    expect(cacheKey({ ...base, params: { repository: "owner/a" } }, "day")).toBe(
      "int_1:stars:day:30d:repository=owner/a",
    );
  });

  it("defaults params so a widget written before this parses", () => {
    const widget = Widget.parse({
      id: "w1",
      kind: "provider_metric",
      integrationId: "int_1",
      metric: "stars",
      customMetricId: null,
      title: null,
      col: 0,
      row: 0,
      position: 0,
    });
    expect(widget.params).toEqual({});
  });

  it("refuses a param key that is not a plain identifier", () => {
    // These reach a cache key and a provider request; the shape is checked
    // before either.
    const parsed = MetricQuery.safeParse({ ...base, params: { "../etc": "x" } });
    expect(parsed.success).toBe(false);
  });

  it("refuses an unbounded number of params", () => {
    const params = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`k${i}`, "v"]));
    expect(MetricQuery.safeParse({ ...base, params }).success).toBe(false);
  });
});
