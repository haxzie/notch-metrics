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

  it("pins a declared freshness to the floor exactly, rather than above it", () => {
    // Worth knowing while reading the manifests: every `freshnessSeconds` in
    // the repository today is 60, 180 or 300, so the clamp puts all of them on
    // the tick. The field still says what the connector *wants*, and starts
    // mattering again the moment the tick moves or a connector asks for more.
    expect(freshnessFor("dodopayments", "one_time_sales", "day")).toBe(WARM_INTERVAL_SECONDS);
  });

  it("leaves a bucket that is already longer than the floor alone", () => {
    // The clamp is a floor, not a replacement. A metric with no declared
    // freshness takes its bucket — an hour for a monthly figure, fifteen
    // minutes for a daily one — and both have to survive.
    expect(freshnessFor("not-a-provider", "revenue", "month")).toBe(3600);
    expect(freshnessFor("not-a-provider", "revenue", "day")).toBe(900);
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
