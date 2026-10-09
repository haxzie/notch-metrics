import { describe, expect, it } from "vitest";
import { credentialExpiry, isRefreshDue } from "../src/oauth.ts";

const policy = { leadTimeMs: 60 * 60 * 1000, minIntervalMs: 5 * 60 * 1000 };
const now = 1_000_000_000_000;

describe("isRefreshDue", () => {
  it("is due inside the lead window and not before", () => {
    const inside = now + policy.leadTimeMs - 1;
    const outside = now + policy.leadTimeMs + 1;
    expect(isRefreshDue(policy, { expiresAt: inside, lastAttemptAt: null }, now)).toBe(true);
    expect(isRefreshDue(policy, { expiresAt: outside, lastAttemptAt: null }, now)).toBe(false);
  });

  it("is due for an unknown expiry, once", () => {
    expect(isRefreshDue(policy, { expiresAt: null, lastAttemptAt: null }, now)).toBe(true);
    expect(isRefreshDue(policy, { expiresAt: null, lastAttemptAt: now - 1000 }, now)).toBe(false);
  });

  it("honours the floor even for a token that has already expired", () => {
    // A loop that refreshes on every tick is how a client id gets throttled.
    const expired = now - 1;
    expect(
      isRefreshDue(
        policy,
        { expiresAt: expired, lastAttemptAt: now - policy.minIntervalMs + 1 },
        now,
      ),
    ).toBe(false);
    expect(
      isRefreshDue(policy, { expiresAt: expired, lastAttemptAt: now - policy.minIntervalMs }, now),
    ).toBe(true);
  });
});

describe("credentialExpiry", () => {
  it("reads a decimal string or a number, and nothing else", () => {
    expect(credentialExpiry({ expires_at: "1700000000000" })).toBe(1_700_000_000_000);
    expect(credentialExpiry({ expires_at: 1_700_000_000_000 })).toBe(1_700_000_000_000);
    expect(credentialExpiry({ expires_at: "soon" })).toBeNull();
    expect(credentialExpiry({ expires_at: "0" })).toBeNull();
    expect(credentialExpiry({})).toBeNull();
  });
});
