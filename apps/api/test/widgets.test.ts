import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
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
  it("stores and returns the app, the row count and the display mode", async () => {
    const { token } = await signedInUser();

    const put = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, rows: 3, display: "list", widgets: [widgetFixture] }),
    });
    expect(put.status).toBe(200);
    expect(await put.json()).toMatchObject({ revision: 1, rows: 3, display: "list" });

    const got = await call("/v1/widgets", token);
    const body = await got.json<{ rows: number; display: string; widgets: { appId: string }[] }>();
    expect(body.rows).toBe(3);
    expect(body.display).toBe("list");
    // The app has to survive the round trip, or a widget whose integration is
    // later disconnected has nothing left to say which app to reconnect.
    expect(scalar(body.widgets[0]).appId).toBe("google-analytics");
  });

  it("defaults rows and display for a client that predates them", async () => {
    const { token } = await signedInUser();
    const put = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, widgets: [] }),
    });
    expect(await put.json()).toMatchObject({ rows: 2, display: "grid" });
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
      body: JSON.stringify({ revision: 0, rows: 4, display: "list", widgets: [widgetFixture] }),
    });

    // A second Mac that still thinks the revision is 0.
    const stale = await call("/v1/widgets", token, {
      method: "PUT",
      body: JSON.stringify({ revision: 0, rows: 1, display: "grid", widgets: [] }),
    });
    expect(stale.status).toBe(409);

    const body = await stale.json<{ code: string; rows: number; display: string }>();
    expect(body.code).toBe("STALE_REVISION");
    // The loser needs the winning state back to merge against, which means it
    // has to include the fields it was about to overwrite.
    expect(body.rows).toBe(4);
    expect(body.display).toBe("list");
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
