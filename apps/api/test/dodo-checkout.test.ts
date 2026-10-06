import { describe, expect, it } from "vitest";
import { billingCountry } from "../src/lib/dodo.ts";

describe("the billing country sent to Dodo", () => {
  it("uses Cloudflare's geolocation when it has one", () => {
    expect(billingCountry("GB")).toBe("GB");
    expect(billingCountry("in")).toBe("IN");
  });

  it("falls back when Cloudflare cannot say", () => {
    // Dodo requires `billing.country` on every subscription. Omitting it is a
    // 422 whose body says only "a field has an invalid value" — so there has
    // to be a value even when there is no signal.
    expect(billingCountry(null)).toBe("US");
    expect(billingCountry(undefined)).toBe("US");
    expect(billingCountry("")).toBe("US");
  });

  it("treats Cloudflare's non-country codes as no signal", () => {
    // XX is Cloudflare's "unknown" and T1 is Tor. Passing either through
    // would be rejected as an invalid ISO country.
    expect(billingCountry("XX")).toBe("US");
    expect(billingCountry("T1")).toBe("US");
    expect(billingCountry("GBR")).toBe("US");
    expect(billingCountry("1")).toBe("US");
  });
});
