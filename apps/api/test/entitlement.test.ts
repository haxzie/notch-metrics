import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { user } from "@notch/db";
import { billingState, hasAccess } from "../src/lib/entitlement.ts";
import { db, makeUser, migrate } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(user);
});

const DAY = 24 * 3600 * 1000;

describe("what the billing facts say about a trial", () => {
  it("reports a live trial as trialing, with access", async () => {
    const u = await makeUser({ plan: "trial", trialEndsAt: new Date(Date.now() + 3 * DAY) });
    const state = await billingState(db(), u.id);

    expect(state.status).toBe("trialing");
    expect(hasAccess(state)).toBe(true);
  });

  /**
   * The bug this pins. Any non-null `trialEndsAt` used to read as `trialing`
   * whatever the date said, so a lapsed account reported itself as still on a
   * trial. `hasAccess` was right either way — it compares the date — but the
   * billing page rendered the fact literally and said "Your trial runs
   * until", with a date in the past, beside an API answering 402.
   */
  it("reports a lapsed trial as expired, not as trialing", async () => {
    const u = await makeUser({ plan: "trial", trialEndsAt: new Date(Date.now() - DAY) });
    const state = await billingState(db(), u.id);

    expect(state.status).toBe("expired");
    expect(hasAccess(state)).toBe(false);
    // The date itself is still reported: the page needs it to say when.
    expect(state.trialEndsAt).not.toBeNull();
  });

  it("reports an account that never had a trial as expired", async () => {
    const u = await makeUser({ plan: "trial", trialEndsAt: null });
    const state = await billingState(db(), u.id);

    expect(state.status).toBe("expired");
    expect(hasAccess(state)).toBe(false);
  });

  /** The verdict and the facts have to agree, whichever way round they are read. */
  it("never says trialing without access, or expired with it", async () => {
    for (const offset of [-5 * DAY, -1, 1, 5 * DAY]) {
      await db().delete(user);
      const u = await makeUser({ plan: "trial", trialEndsAt: new Date(Date.now() + offset) });
      const state = await billingState(db(), u.id);
      expect(state.status === "trialing").toBe(hasAccess(state));
    }
  });
});
