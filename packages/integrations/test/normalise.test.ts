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

  /**
   * 401 and 403 used to be left bare, on the reasoning that "rejected the
   * credentials" says everything. It does for a mistyped key and not for a
   * scoped one, and the gap cost a real signup: a Stripe restricted key
   * missing one permission returns a 403 naming that permission, and the
   * user saw only the number and went off to make another key.
   */
  it("attaches the provider's own message to a 403", async () => {
    const error = await errorForResponse(
      "api.stripe.com",
      response(403, {
        error: {
          code: "more_permissions_required",
          message:
            "Permission denied. Enabling Account read ('account_read') permissions on this key would allow this request to continue.",
        },
      }),
    );
    expect(error.code).toBe("auth_failed");
    expect(error.message).toContain("rejected the credentials (403)");
    expect(error.message).toContain("account_read");
  });

  it("redacts a key the provider echoed back, however short", async () => {
    // The failure this prevents: OpenAI names the key it refused, truncated.
    // A redaction pattern tuned to the length of a whole key prints the
    // fragment, and the fragment is still the start of a live credential.
    const error = await errorForResponse(
      "api.openai.com",
      response(401, { error: { message: "Incorrect API key provided: sk-abc" } }),
    );
    expect(error.code).toBe("auth_failed");
    expect(error.message).not.toContain("sk-abc");
    expect(error.message).toContain("Incorrect API key provided");
  });

  /**
   * Providers append a console deep link, which is a couple of hundred
   * characters of account id and query string. Cutting the URL alone leaves
   * "You can edit permissions at ." on screen, so the sentence goes with it.
   */
  it("drops a sentence whose point was a link", async () => {
    const error = await errorForResponse(
      "api.stripe.com",
      response(403, {
        error: {
          message:
            "Permission denied. You can edit permissions at https://dashboard.stripe.com/b/acct_1?destination=%2Ftest%2Fapikeys.",
        },
      }),
    );
    expect(error.message).toContain("Permission denied.");
    expect(error.message).not.toContain("http");
    expect(error.message).not.toMatch(/\bat\s*\.?\s*$/);
  });

  it("still says nothing extra on a 429, which Retry-After already covers", async () => {
    const error = await errorForResponse(
      "api.stripe.com",
      response(429, { error: { message: "Too many requests hit the API too quickly." } }),
    );
    expect(error.code).toBe("rate_limited");
    expect(error.message).toBe("api.stripe.com asked us to wait");
  });

  it("reads the body shapes the connectors actually receive", async () => {
    // One case each for Shopify/GitHub's `errors` array and FastAPI's
    // `detail`, both of which used to fall through to the bare status.
    const fromErrors = await errorForResponse(
      "shop.myshopify.com",
      response(400, { errors: [{ message: "Field 'orders' doesn't exist" }] }),
    );
    expect(fromErrors.message).toContain("doesn't exist");

    const fromDetail = await errorForResponse(
      "api.polar.sh",
      response(422, { detail: "organization_id is not a valid uuid" }),
    );
    expect(fromDetail.message).toContain("not a valid uuid");
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
