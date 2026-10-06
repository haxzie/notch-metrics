import { describe, expect, it } from "vitest";
import { connectionName } from "../src/naming.ts";
import { getAdapter } from "../src/registry.ts";

const stripe = getAdapter("stripe").manifest;
const dodo = getAdapter("dodopayments").manifest;

describe("naming a new connection", () => {
  it("joins the provider and what verify() learned", () => {
    expect(connectionName({ manifest: stripe, accountLabel: "Acme Inc" })).toBe(
      "Stripe — Acme Inc",
    );
  });

  it("falls back to the provider when there is no detail", () => {
    expect(connectionName({ manifest: stripe, accountLabel: null })).toBe("Stripe");
    expect(connectionName({ manifest: stripe, accountLabel: "   " })).toBe("Stripe");
    expect(connectionName({ manifest: stripe })).toBe("Stripe");
  });

  it("does not repeat the provider's own name", () => {
    // An adapter that returns its own name, or an account actually called
    // "Stripe", must not produce "Stripe — Stripe".
    expect(connectionName({ manifest: stripe, accountLabel: "Stripe" })).toBe("Stripe");
    expect(connectionName({ manifest: dodo, accountLabel: "Dodo Payments (test)" })).toBe(
      "Dodo Payments (test)",
    );
  });

  it("disambiguates against names already in use", () => {
    // Two Stripe accounts with no business name set would otherwise both be
    // "Stripe", and the list could not tell them apart.
    expect(connectionName({ manifest: stripe, taken: ["Stripe"] })).toBe("Stripe (2)");
    expect(connectionName({ manifest: stripe, taken: ["Stripe", "Stripe (2)"] })).toBe(
      "Stripe (3)",
    );
  });

  it("only disambiguates on an exact clash", () => {
    expect(connectionName({ manifest: stripe, accountLabel: "Acme", taken: ["Stripe"] })).toBe(
      "Stripe — Acme",
    );
  });

  it("gives every connector a usable name with no detail at all", () => {
    for (const id of ["stripe", "dodopayments", "lemonsqueezy", "github"] as const) {
      const name = connectionName({ manifest: getAdapter(id).manifest });
      expect(name.length).toBeGreaterThan(0);
      expect(name).not.toContain("—");
    }
  });
});
