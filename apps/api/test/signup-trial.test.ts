import { createExecutionContext, env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { user } from "@notch/db";
import worker from "../src/index.ts";
import { db, migrate } from "./helpers.ts";
import { TRIAL_DAYS } from "../src/lib/entitlement.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(user);
});

const ctx = createExecutionContext();

async function signUp(email: string) {
  return worker.fetch(
    new Request("http://localhost:8787/api/auth/sign-up/email", {
      method: "POST",
      headers: { "content-type": "application/json", origin: "http://localhost:3000" },
      body: JSON.stringify({ email, password: "a-long-enough-password", name: "Test" }),
    }),
    env,
    ctx,
  );
}

describe("signing up", () => {
  it("grants the trial, so a new account is not born expired", async () => {
    // Without the create hook `trial_ends_at` stays null, `hasAccess` is
    // false from the very first request, and the notch never loads a metric.
    const response = await signUp("new@example.com");
    expect(response.status).toBe(200);

    const [row] = await db().select().from(user).limit(1);
    expect(row?.trialEndsAt).toBeInstanceOf(Date);

    const days = (row!.trialEndsAt!.getTime() - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(TRIAL_DAYS - 0.1);
    expect(days).toBeLessThanOrEqual(TRIAL_DAYS);
  });

  it("reports the account as trialing, with access", async () => {
    const signUpResponse = await signUp("trial@example.com");
    const cookie = signUpResponse.headers.get("set-cookie") ?? "";

    const me = await worker.fetch(
      new Request("http://localhost:8787/v1/me", { headers: { cookie } }),
      env,
      ctx,
    );
    const body = (await me.json()) as { billing: { plan: string; status: string } };
    expect(body.billing.plan).toBe("trial");
    expect(body.billing.status).toBe("trialing");
  });
});
