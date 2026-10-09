import { env } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { notify } from "../src/lib/slack.ts";
import type { Env } from "../src/env.ts";

const SIGNUPS = "https://hooks.slack.com/services/T000/B000/signups";
const EVENTS = "https://hooks.slack.com/services/T000/B111/events";

/** The posts a run made, as `[url, text]`. */
function recorder() {
  const posts: [string, string][] = [];
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    posts.push([String(url), JSON.parse(String(init.body)).text]);
    return new Response("ok");
  });
  return posts;
}

function configured(overrides: Partial<Env> = {}): Env {
  return {
    ...env,
    SLACK_WEBHOOK_SIGNUPS: SIGNUPS,
    SLACK_WEBHOOK_EVENTS: EVENTS,
    ...overrides,
  } as Env;
}

describe("slack notifications", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("sends signups and connection events to different webhooks", async () => {
    const posts = recorder();
    await notify(configured(), { kind: "signup", email: "jane@example.com", name: "Jane" });
    await notify(configured(), {
      kind: "integration_connected",
      provider: "stripe",
      account: "Acme Inc",
      email: "jane@example.com",
    });

    expect(posts.map(([url]) => url)).toEqual([SIGNUPS, EVENTS]);
  });

  it("keeps a message to one short line", async () => {
    const posts = recorder();
    await notify(configured(), {
      kind: "integration_connected",
      provider: "stripe",
      account: "Acme Inc",
      email: "jane@example.com",
    });
    const text = posts[0]?.[1] ?? "";
    expect(text).toBe(":link: Connected stripe · Acme Inc · jane@example.com");
    expect(text).not.toContain("\n");
  });

  it("does nothing at all when a channel has no webhook", async () => {
    const posts = recorder();
    // The state of every test run and of a dev stack whose owner did not want
    // their Slack filling up. It must not be an error.
    await notify({ ...env, SLACK_WEBHOOK_SIGNUPS: undefined } as Env, {
      kind: "signup",
      email: "jane@example.com",
    });
    expect(posts).toHaveLength(0);
  });

  it("refuses to post user emails anywhere but hooks.slack.com", async () => {
    const posts = recorder();
    await notify(configured({ SLACK_WEBHOOK_SIGNUPS: "https://evil.example.com/collect" }), {
      kind: "signup",
      email: "jane@example.com",
    });
    expect(posts).toHaveLength(0);
  });

  it("swallows a Slack outage rather than failing the caller", async () => {
    vi.stubGlobal("fetch", async () => {
      throw new Error("connection reset");
    });
    await expect(
      notify(configured(), { kind: "signup", email: "jane@example.com" }),
    ).resolves.toBeUndefined();
  });

  it("swallows a revoked webhook, which Slack reports as a 404", async () => {
    vi.stubGlobal("fetch", async () => new Response("invalid_token", { status: 404 }));
    await expect(
      notify(configured(), {
        kind: "integration_broken",
        provider: "stripe",
        account: "Acme Inc",
        email: null,
      }),
    ).resolves.toBeUndefined();
  });

  it("omits an unknown email rather than printing a blank field", async () => {
    const posts = recorder();
    await notify(configured(), {
      kind: "integration_disconnected",
      provider: "github",
      account: "haxzie/notch-metrics",
      email: null,
    });
    expect(posts[0]?.[1]).toBe(":heavy_minus_sign: Disconnected github · haxzie/notch-metrics");
  });
});
