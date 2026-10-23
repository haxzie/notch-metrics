import { describe, expect, it } from "vitest";
import { DEFAULT_GRANULARITY } from "@notch/schemas";
import { cacheKey, freshnessFor, WARM_INTERVAL_SECONDS } from "../src/lib/metric-cache.ts";

describe("cache freshness", () => {
  /**
   * The specific regression: Dodo's money metrics declared 60 seconds against
   * a 300-second tick, so every row the cron wrote had expired before the next
   * tick could rewrite it. The tile was never once served from cache while
   * three `/payments` walks ran every five minutes on its behalf.
   */
  it("never lets a metric ask for a TTL shorter than the warm interval", () => {
    expect(freshnessFor("dodopayments", "one_time_sales", "day")).toBeGreaterThanOrEqual(
      WARM_INTERVAL_SECONDS,
    );
    expect(freshnessFor("dodopayments", "revenue", "day")).toBeGreaterThanOrEqual(
      WARM_INTERVAL_SECONDS,
    );
  });

  it("still honours a descriptor that asks for longer than the floor", () => {
    // A monthly bucket's default is an hour, which is well above the floor and
    // must survive the clamp — the clamp is a floor, not a replacement.
    expect(freshnessFor("stripe", "mrr", "month")).toBeGreaterThan(WARM_INTERVAL_SECONDS);
  });

  it("falls back to the bucket for a provider the registry does not know", () => {
    expect(freshnessFor("not-a-provider", "revenue", "week")).toBeGreaterThanOrEqual(
      WARM_INTERVAL_SECONDS,
    );
  });
});

describe("warm/read key parity", () => {
  /**
   * The invariant the whole refresh story rests on: what the cron writes and
   * what the notch reads must be the same string. The cron used to warm a
   * hardcoded `30d`, so a 90-day tile was warmed never and a 30-day tile was
   * warmed whether or not it existed — warming that could not produce a hit.
   */
  it("matches a widget's warm target to the query the app sends for it", () => {
    const widget = {
      integrationId: "int_1",
      metric: "one_time_sales",
      granularity: "day" as const,
      range: "90d" as const,
      params: {},
    };
    const appQuery = {
      integrationId: "int_1",
      metric: "one_time_sales" as const,
      granularity: "day" as const,
      range: "90d" as const,
      series: true,
      params: {},
    };

    expect(cacheKey(widget, widget.granularity)).toBe(
      cacheKey(appQuery, appQuery.granularity ?? DEFAULT_GRANULARITY[appQuery.range]),
    );
  });

  it("separates two ranges of one metric, because they are two numbers", () => {
    const base = { integrationId: "int_1", metric: "revenue", params: {} };
    expect(cacheKey({ ...base, range: "30d" }, "day")).not.toBe(
      cacheKey({ ...base, range: "90d" }, "day"),
    );
  });
});
