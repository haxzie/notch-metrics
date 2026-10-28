import { env } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { capture, identifyEvent } from "../src/lib/analytics.ts";
import { track } from "../src/lib/track.ts";
import type { Env } from "../src/env.ts";

const TOKEN = "phc_test_token";
const SIGNUPS = "https://hooks.slack.com/services/T000/B000/signups";
const EVENTS = "https://hooks.slack.com/services/T000/B111/events";

interface Post {
  url: string;
  body: Record<string, unknown>;
}

/** Every POST a run made, parsed. */
function recorder() {
  const posts: Post[] = [];
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    posts.push({ url: String(url), body: JSON.parse(String(init.body)) });
    return new Response("ok");
  });
  return posts;
}

function configured(overrides: Partial<Env> = {}): Env {
  return {
    ...env,
    POSTHOG_PROJECT_TOKEN: TOKEN,
    POSTHOG_HOST: "https://us.i.posthog.com",
    SLACK_WEBHOOK_SIGNUPS: SIGNUPS,
    SLACK_WEBHOOK_EVENTS: EVENTS,
    ...overrides,
  } as Env;
}

const posthog = (posts: Post[]) => posts.filter((p) => p.url.includes("posthog"));
const slack = (posts: Post[]) => posts.filter((p) => p.url.includes("hooks.slack.com"));

function batch(post: Post): Record<string, unknown>[] {
  return (post.body.batch ?? []) as Record<string, unknown>[];
}
function props(event: Record<string, unknown>): Record<string, unknown> {
  return (event.properties ?? {}) as Record<string, unknown>;
}

describe("the posthog transport", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("posts to /batch/ with the project token", async () => {
    const posts = recorder();
    await capture(configured(), [{ event: "widget_added", distinctId: "usr_1" }]);

    const post = posthog(posts)[0];
    expect(post?.url).toBe("https://us.i.posthog.com/batch/");
    expect(post?.body.api_key).toBe(TOKEN);
  });

  it("puts distinct_id inside properties, which is where /batch/ reads it", async () => {
    // At the top level it is accepted with a 200 and the event loses its
    // identity, which is the worst failure available here.
    const posts = recorder();
    await capture(configured(), [{ event: "widget_added", distinctId: "usr_1" }]);

    const event = batch(posthog(posts)[0]!)[0]!;
    expect(props(event).distinct_id).toBe("usr_1");
    expect(event.distinct_id).toBeUndefined();
  });

  it("sends one request for many events", async () => {
    const posts = recorder();
    await capture(
      configured(),
      Array.from({ length: 12 }, (_, i) => ({ event: "widget_added", distinctId: `usr_${i}` })),
    );

    expect(posthog(posts)).toHaveLength(1);
    expect(batch(posthog(posts)[0]!)).toHaveLength(12);
  });

  it("caps a batch rather than sending a payload that gets rejected whole", async () => {
    const posts = recorder();
    await capture(
      configured(),
      Array.from({ length: 200 }, () => ({ event: "widget_added", distinctId: "usr_1" })),
    );

    expect(batch(posthog(posts)[0]!)).toHaveLength(50);
  });

  it("does nothing at all without a token", async () => {
    // Every test run and any dev stack whose owner does not want their funnel
    // full of fake signups.
    const posts = recorder();
    await capture({ ...env, POSTHOG_PROJECT_TOKEN: undefined } as Env, [
      { event: "widget_added", distinctId: "usr_1" },
    ]);

    expect(posts).toHaveLength(0);
  });

  it("swallows a rejected batch, because a request must not fail with it", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.stubGlobal("fetch", async () => new Response("bad", { status: 400 }));

    await expect(
      capture(configured(), [{ event: "widget_added", distinctId: "usr_1" }]),
    ).resolves.toBeUndefined();
    expect(errors).toHaveBeenCalled();
    errors.mockRestore();
  });

  it("swallows a dead host too", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.stubGlobal("fetch", async () => Promise.reject(new Error("econnrefused")));

    await expect(
      capture(configured(), [{ event: "widget_added", distinctId: "usr_1" }]),
    ).resolves.toBeUndefined();
    errors.mockRestore();
  });

  it("identifies by user id and sets the person's fields", async () => {
    const event = identifyEvent({ id: "usr_1", email: "jane@example.com", name: "Jane" });
    expect(event.event).toBe("$identify");
    expect(event.distinctId).toBe("usr_1");
    expect(event.properties?.$set).toEqual({ email: "jane@example.com", name: "Jane" });
  });
});

describe("the event fan-out", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("sends a signup to both Slack and PostHog, identity first", async () => {
    const posts = recorder();
    await track(configured(), {
      kind: "signed_up",
      userId: "usr_1",
      email: "jane@example.com",
      name: "Jane",
    });

    expect(slack(posts)).toHaveLength(1);
    const events = batch(posthog(posts)[0]!);
    // Identity before the event that mentions them, or the first thing
    // PostHog knows about this person is an anonymous id.
    expect(events.map((e) => e.event)).toEqual(["$identify", "user_signed_up"]);

    // The address and the name reach PostHog once, in $set, and are not
    // repeated onto the event itself.
    expect(events[0]!.properties).toMatchObject({
      $set: { email: "jane@example.com", name: "Jane" },
    });
    const signup = JSON.stringify(props(events[1]!));
    expect(signup).not.toContain("jane@example.com");
    expect(signup).not.toContain("Jane");
  });

  it("keeps an email off an ordinary event's properties", async () => {
    // `telemetry.ts` refuses an address in the log store. The compromise here
    // is that it reaches PostHog only inside $identify's $set.
    const posts = recorder();
    await track(configured(), {
      kind: "integration_connected",
      userId: "usr_1",
      email: "jane@example.com",
      provider: "stripe",
      account: "Acme Inc",
    });

    const event = batch(posthog(posts)[0]!)[0]!;
    expect(event.event).toBe("integration_connected");
    expect(JSON.stringify(props(event))).not.toContain("jane@example.com");
    // The properties that are worth having are all still there.
    expect(props(event).provider).toBe("stripe");
    expect(props(event).account).toBe("Acme Inc");
    expect(props(event).distinct_id).toBe("usr_1");
  });

  it("keeps the noisy events out of Slack", async () => {
    // A channel that posts every sign-in and every drag is a channel that
    // gets muted, taking the signups with it.
    const posts = recorder();
    await track(configured(), [
      { kind: "signed_in", userId: "usr_1", email: "jane@example.com" },
      {
        kind: "widget_added",
        userId: "usr_1",
        widgetKind: "provider_metric",
        appId: "stripe",
        metric: "mrr",
        size: "2x1",
        chart: "sparkline",
        range: "30d",
      },
      { kind: "layout_saved", userId: "usr_1", widgets: 4, rows: 2, revision: 7 },
    ]);

    expect(slack(posts)).toHaveLength(0);
    expect(batch(posthog(posts)[0]!).map((e) => e.event)).toEqual([
      "$identify",
      "user_signed_in",
      "widget_added",
      "layout_saved",
    ]);
  });

  it("names the custom app in Slack, since the name is the only new part", async () => {
    const posts = recorder();
    await track(configured(), {
      kind: "custom_app_added",
      userId: "usr_1",
      email: "jane@example.com",
      appId: "plausible",
      name: "Plausible visitors",
      customMetricId: "plg_visitors",
    });

    const text = slack(posts)[0]?.body.text as string;
    expect(text).toContain("Plausible visitors");
    expect(slack(posts)[0]?.url).toBe(EVENTS);
    expect(batch(posthog(posts)[0]!)[0]?.event).toBe("custom_app_added");
  });

  it("sends one batch for many events", async () => {
    const posts = recorder();
    await track(configured(), [
      {
        kind: "widget_added",
        userId: "usr_1",
        widgetKind: "provider_metric",
        appId: "stripe",
        metric: "mrr",
        size: "2x1",
        chart: "sparkline",
        range: "30d",
      },
      {
        kind: "widget_removed",
        userId: "usr_1",
        widgetKind: "provider_metric",
        appId: "github",
        metric: "stars",
      },
    ]);

    expect(posthog(posts)).toHaveLength(1);
    expect(batch(posthog(posts)[0]!)).toHaveLength(2);
  });

  it("resolves when nothing is configured, and sends nothing", async () => {
    const posts = recorder();
    await expect(
      track({ ...env, POSTHOG_PROJECT_TOKEN: undefined } as Env, {
        kind: "layout_saved",
        userId: "usr_1",
        widgets: 1,
        rows: 2,
        revision: 1,
      }),
    ).resolves.toBeUndefined();
    expect(posts).toHaveLength(0);
  });

  it("hands the work to waitUntil when it is given one", async () => {
    const posts = recorder();
    const pending: Promise<unknown>[] = [];
    await track(
      configured(),
      { kind: "layout_saved", userId: "usr_1", widgets: 1, rows: 2, revision: 1 },
      (p) => pending.push(p),
    );

    expect(pending).toHaveLength(1);
    await Promise.all(pending);
    expect(posthog(posts)).toHaveLength(1);
  });
});
