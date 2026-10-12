import { describe, expect, it } from "vitest";
import { DEFAULT_GRANULARITY, TimeRange } from "@notch/schemas";
import { manifests } from "../src/registry.ts";

/**
 * `granularities` decides which ranges the configure pane offers.
 *
 * It was dead metadata for a long time — declared by every connector and
 * read by nothing — so the pane offered all five ranges for every metric and
 * the ones a provider could not serve came back as errors on the tile. Now
 * that it is load-bearing, a wrong declaration is a missing control rather
 * than a harmless comment, which is what these guard.
 */
const seriesMetrics = manifests().flatMap((manifest) =>
  manifest.metrics
    .filter((metric) => metric.supportsSeries || metric.supportsCompare)
    .map((metric) => [`${manifest.id}.${metric.id}`, metric] as const),
);

function offeredRanges(granularities: readonly string[]): TimeRange[] {
  return TimeRange.options.filter((range) => granularities.includes(DEFAULT_GRANULARITY[range]));
}

describe("the ranges a metric offers", () => {
  it("every windowed metric declares at least one granularity", () => {
    for (const [name, metric] of seriesMetrics) {
      expect(metric.granularities, name).not.toHaveLength(0);
    }
  });

  /**
   * The failure this prevents is a Range row with an empty popup. A metric
   * declaring only `month` would offer nothing, because no range maps to a
   * monthly bucket on its own — `12m` does, but only as `DEFAULT_GRANULARITY`
   * says so, and a metric is free to declare a granularity no range selects.
   */
  it("every windowed metric offers at least one range", () => {
    for (const [name, metric] of seriesMetrics) {
      expect(offeredRanges(metric.granularities), name).not.toHaveLength(0);
    }
  });

  /**
   * Pins the mapping the Mac duplicates in `TimeRange.defaultGranularity`.
   * The pane cannot wait for the network to lay out a picker, so the table
   * exists twice; this is the half that fails first if they drift.
   */
  it("maps each range to the bucket the Mac expects", () => {
    expect(DEFAULT_GRANULARITY).toEqual({
      "24h": "hour",
      "7d": "day",
      "30d": "day",
      "90d": "week",
      "12m": "month",
    });
  });

  /** A snapshot has no window, so a granularity on one is noise. */
  it("documents which metrics offer fewer than every range", () => {
    const narrowed = seriesMetrics
      .filter(([, metric]) => offeredRanges(metric.granularities).length < TimeRange.options.length)
      .map(([name]) => name);

    // Not an assertion about the right answer — a record of the current one,
    // so widening or narrowing a connector's ranges is a visible diff rather
    // than something a user discovers on a tile.
    expect(narrowed.length).toBeGreaterThan(0);
    expect(narrowed).toContain("anthropic.api_spend");
    expect(narrowed).toContain("openai.api_spend");
  });
});
