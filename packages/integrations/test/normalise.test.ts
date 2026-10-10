import { describe, expect, it } from "vitest";
import { bucketStart, instantOfWallClock } from "../src/normalise.ts";

describe("instantOfWallClock", () => {
  it("reads a label as the zone's wall clock, not as UTC", () => {
    // 14:00 British Summer Time is 13:00Z. Reading the label as UTC would
    // file a Plausible bar an hour late for every user east of Greenwich.
    expect(
      instantOfWallClock({ year: 2026, month: 10, day: 5, hour: 14 }, "Europe/London"),
    ).toEqual(new Date("2026-10-05T13:00:00.000Z"));
  });

  it("uses the offset in force on the day, not a fixed one", () => {
    expect(instantOfWallClock({ year: 2026, month: 12, day: 5 }, "Europe/London")).toEqual(
      new Date("2026-12-05T00:00:00.000Z"),
    );
  });

  it("lands on the right side of a spring-forward", () => {
    // 8 March 2026 is when New York loses an hour. Sampling the offset once,
    // at the naive instant, still reads EST and puts this at 08:00Z — an
    // hour out, which for an hourly bucket is the whole bucket.
    expect(
      instantOfWallClock({ year: 2026, month: 3, day: 8, hour: 3 }, "America/New_York"),
    ).toEqual(new Date("2026-03-08T07:00:00.000Z"));
  });

  it("round-trips a day through `bucketStart`", () => {
    // The two are inverses, and a provider's day label has to come back as
    // that same day or every bar shifts by one.
    const at = instantOfWallClock({ year: 2026, month: 10, day: 5 }, "Asia/Tokyo");
    expect(bucketStart(at, "day", "Asia/Tokyo")).toEqual(new Date("2026-10-05T00:00:00.000Z"));
  });
});
