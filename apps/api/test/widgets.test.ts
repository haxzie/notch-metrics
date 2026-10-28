import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { deviceToken, user, widget, widgetRevision } from "@notch/db";
import worker from "../src/index.ts";
import { id, randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(widget);
  await db().delete(widgetRevision);
  await db().delete(deviceToken);
  await db().delete(user);
});

const ctx = createExecutionContext();

/** A device token, which is how the Mac app talks to this route. */
async function signedInUser() {
  const u = await makeUser();
  const token = randomToken(32);
  await db()
    .insert(deviceToken)
    .values({
      id: id("dev"),
      tokenHash: await sha256Base64Url(token),
      userId: u.id,
      label: "Test Mac",
    });
  await db().insert(widgetRevision).values({ userId: u.id, revision: 0 }).onConflictDoNothing();
  return { user: u, token };
}

function call(path: string, token: string, init: RequestInit = {}) {
  return worker.fetch(
    new Request(`http://localhost:8787${path}`, {
      ...init,
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    }),
    env,
    ctx,
  );
}

const widgetFixture = {
  id: "wid_1",
  kind: "provider_metric",
  appId: "google-analytics",
  integrationId: null,
  metric: "active_subscribers",
  customMetricId: null,
  title: "Active users",
  size: "2x2",
  col: 0,
  row: 0,
  position: 0,
  granularity: "day",
  range: "30d",
  chart: "sparkline",
  visible: true,
};

describe("layout round-trip", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("stores and returns the app and the row count", async () => {
    const { token } = await signedInUser();

    const put = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, rows: 3, widgets: [widgetFixture] }),
    });
    expect(put.status).toBe(200);
    expect(await put.json()).toMatchObject({ revision: 1, rows: 3 });

    const got = await call("/v1/widgets", token);
    const body = await got.json<{ rows: number; widgets: { appId: string }[] }>();
    expect(body.rows).toBe(3);
    // The app has to survive the round trip, or a widget whose integration is
    // later disconnected has nothing left to say which app to reconnect.
    expect(scalar(body.widgets[0]).appId).toBe("google-analytics");
  });

  it("defaults the row count for a client that predates it", async () => {
    const { token } = await signedInUser();
    const put = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, widgets: [] }),
    });
    expect(await put.json()).toMatchObject({ rows: 2 });
  });

  it("defaults appId rather than rejecting a widget without one", async () => {
    const { token } = await signedInUser();
    const { appId: _omitted, ...legacy } = widgetFixture;
    const put = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, widgets: [legacy] }),
    });
    expect(put.status).toBe(200);

    const body = await (await call("/v1/widgets", token)).json<{ widgets: { appId: string }[] }>();
    expect(scalar(body.widgets[0]).appId).toBe("unknown");
  });

  it("returns the winning state on a stale revision rather than clobbering", async () => {
    const { token } = await signedInUser();
    await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, rows: 4, widgets: [widgetFixture] }),
    });

    // A second Mac that still thinks the revision is 0.
    const stale = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, rows: 1, widgets: [] }),
    });
    expect(stale.status).toBe(409);

    const body = await stale.json<{ code: string; rows: number }>();
    expect(body.code).toBe("STALE_REVISION");
    // The loser needs the winning state back to merge against, which means it
    // has to include the fields it was about to overwrite.
    expect(body.rows).toBe(4);
  });

  it("reports what the save changed, once the rows are written", async () => {
    // The wiring, not the diff: `layout-events.test.ts` covers the inference.
    // What this checks is that the route reads the old list before replacing
    // it, and reports after the insert rather than before.
    const posts: Record<string, unknown>[] = [];
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      if (String(url).includes("posthog")) posts.push(JSON.parse(String(init.body)));
      return new Response("ok");
    });

    const { token } = await signedInUser();
    const analytics = { ...env, POSTHOG_PROJECT_TOKEN: "phc_test" };
    const put = (revision: number, widgets: unknown[]) =>
      worker.fetch(
        new Request("http://localhost:8787/v1/widgets", {
          method: "PUT",
          headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
          body: JSON.stringify({ revision, widgets }),
        }),
        analytics,
        ctx,
      );

    await put(0, [widgetFixture]);
    await put(1, []);

    const names = posts.flatMap((body) =>
      ((body.batch ?? []) as { event: string }[]).map((e) => e.event),
    );
    expect(names).toContain("widget_added");
    expect(names).toContain("widget_removed");
    expect(names).toContain("layout_saved");

    // And the rows really are gone, so the removal was not reported early.
    const left = await (await call("/v1/widgets", token)).json<{ widgets: unknown[] }>();
    expect(left.widgets).toHaveLength(0);
  });

  it("refuses another user's layout without confirming it exists", async () => {
    const a = await signedInUser();
    const b = await signedInUser();
    await call("/v1/widgets", a.token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, widgets: [widgetFixture] }),
    });

    const theirs = await (await call("/v1/widgets", b.token)).json<{ widgets: unknown[] }>();
    expect(theirs.widgets).toHaveLength(0);
  });
});
