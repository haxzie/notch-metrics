import { describe, expect, it } from "vitest";
import { bucketStart, instantOfWallClock } from "../src/normalise.ts";
import { errorForResponse } from "../src/http.ts";

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

describe("errorForResponse", () => {
  function response(status: number, body: unknown, ok = false) {
    return {
      ok,
      status,
      headers: new Headers(),
      json: async <T>() => body as T,
      text: async () => JSON.stringify(body),
    };
  }

  /**
   * The failure this prevents: a 400 is the provider naming the parameter it
   * refused, and the status alone names nothing. "api.anthropic.com returned
   * 400" on a tile sends somebody to re-check credentials that were never the
   * problem.
   */
  it("attaches the provider's own message to a 400", async () => {
    const error = await errorForResponse(
      "api.anthropic.com",
      response(400, { error: { message: "limit: must be >= 7 for bucket_width 1d" } }),
    );
    expect(error.code).toBe("bad_response");
    expect(error.message).toContain("api.anthropic.com returned 400");
    expect(error.message).toContain("must be >= 7");
  });

  it("leaves 401 alone", async () => {
    // Our own sentence about admin keys is better than "invalid x-api-key",
    // and both at once reads as two separate problems.
    const error = await errorForResponse(
      "api.openai.com",
      response(401, { error: { message: "Incorrect API key provided: sk-abc" } }),
    );
    expect(error.code).toBe("auth_failed");
    expect(error.message).not.toContain("sk-abc");
  });

  it("does not paste in a 500's HTML error page", async () => {
    const error = await errorForResponse("api.openai.com", response(503, "<html>oops</html>"));
    expect(error.code).toBe("provider_down");
    expect(error.message).toBe("api.openai.com returned 503");
  });

  it("falls back to the bare status when the body is not JSON", async () => {
    const broken = {
      ok: false,
      status: 400,
      headers: new Headers(),
      json: async () => {
        throw new SyntaxError("not json");
      },
      text: async () => "nope",
    };
    const error = await errorForResponse("api.anthropic.com", broken);
    expect(error.message).toBe("api.anthropic.com returned 400");
  });
});
