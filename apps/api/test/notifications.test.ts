import { createExecutionContext, env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import {
  deviceToken,
  integration as integrationTable,
  notification,
  notificationCursor,
  notificationState,
  notificationSubscription,
  user,
} from "@notch/db";
import worker from "../src/index.ts";
import { id, randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import type { RawEvent } from "@notch/integrations";
import {
  emit,
  emitConnectionBroken,
  evaluate,
  evaluateEvents,
  inQuietHours,
  markRead,
  percentMove,
  seedSubscriptions,
  thresholdState,
} from "../src/lib/notifications.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(notification);
  await db().delete(notificationCursor);
  await db().delete(notificationSubscription);
  await db().delete(notificationState);
  await db().delete(integrationTable);
  await db().delete(deviceToken);
  await db().delete(user);
});

const ctx = createExecutionContext();

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
  return { user: u, token };
}

async function makeIntegration(userId: string, provider = "stripe") {
  const rowId = id("int");
  await db()
    .insert(integrationTable)
    .values({
      id: rowId,
      userId,
      provider,
      label: "Acme Inc",
      accountLabel: "acct_1Nx · Acme Inc",
      // Not real crypto — the evaluator never opens these, because it works on
      // a series the caller already fetched.
      credentialCiphertext: "x",
      credentialIv: "x",
      credentialWrappedDek: "x",
      keyVersion: 1,
      credentialHint: "rk_live_…4f2a",
      credentialFingerprint: `fp_${rowId}`,
      enabledMetrics: ["mrr"],
      availableMetrics: ["mrr", "recent_payments"],
      refreshOffsetSeconds: 0,
    });
  return rowId;
}

function call(path: string, token: string, init: RequestInit = {}) {
  return worker.fetch(
    new Request(`http://localhost:8787${path}`, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        // Spread last, so a caller can add `if-none-match` without having to
        // restate the auth header.
        ...(init.headers as Record<string, string> | undefined),
      },
    }),
    env,
    ctx,
  );
}

function series(overrides: Record<string, unknown> = {}) {
  return {
    ok: true as const,
    series: {
      integrationId: "int_x",
      metric: "mrr",
      unit: "currency",
      currency: "USD",
      value: 1_000_000,
      previousValue: 900_000,
      delta: null,
      points: [],
      granularity: "day",
      range: "30d",
      from: new Date(Date.now() - 86_400_000).toISOString(),
      to: new Date().toISOString(),
      format: null,
      generatedAt: new Date().toISOString(),
      stale: false,
      ...overrides,
    },
  } as never;
}

/** `Response.json()` is `unknown`; these name only what the assertions read. */
interface FeedBody {
  seq: number;
  unread: number;
  items: { id: string; title: string; typeId: string }[];
  connections: { integrationId: string | null; unread: number }[];
  hasMore: boolean;
  oldestSeq: number | null;
  truncated: boolean;
}

interface SettingsBody {
  code?: string;
  revision: number;
  enabled: boolean;
  quietFromMinute: number | null;
  quietToMinute: number | null;
  subscriptions: unknown[];
}

describe("quiet hours", () => {
  it("handles a window that crosses midnight", () => {
    // The case everybody gets wrong, and the reason this is a pure function.
    expect(inQuietHours(23 * 60, 22 * 60, 8 * 60)).toBe(true);
    expect(inQuietHours(2 * 60, 22 * 60, 8 * 60)).toBe(true);
    expect(inQuietHours(12 * 60, 22 * 60, 8 * 60)).toBe(false);
    expect(inQuietHours(8 * 60, 22 * 60, 8 * 60)).toBe(false);
  });

  it("handles a same-day window, and treats an empty one as off", () => {
    expect(inQuietHours(10 * 60, 9 * 60, 17 * 60)).toBe(true);
    expect(inQuietHours(18 * 60, 9 * 60, 17 * 60)).toBe(false);
    expect(inQuietHours(10 * 60, 9 * 60, 9 * 60)).toBe(false);
    expect(inQuietHours(10 * 60, null, null)).toBe(false);
  });
});

describe("threshold arithmetic", () => {
  it("reports which side of the bound a reading sits on", () => {
    expect(thresholdState(11, "above", 10)).toBe("above");
    expect(thresholdState(9, "above", 10)).toBe("below");
    // Exactly on the line is not across it, in either direction.
    expect(thresholdState(10, "above", 10)).toBe("below");
    expect(thresholdState(10, "below", 10)).toBe("below");
    expect(thresholdState(9, "below", 10)).toBe("above");
  });

  it("has nothing to say without a previous reading", () => {
    expect(percentMove(110, null)).toBeNull();
    // Dividing by a zero baseline is how a notification claims an infinite rise.
    expect(percentMove(110, 0)).toBeNull();
    expect(percentMove(110, 100)).toBeCloseTo(10);
    expect(percentMove(90, 100)).toBeCloseTo(-10);
  });
});

describe("emit", () => {
  it("writes once for a repeated dedupe key, and does not inflate unread", async () => {
    const u = await makeUser();
    const first = await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Payment received",
      occurredAt: new Date(),
      dedupeKey: "k1",
    });
    const second = await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Payment received",
      occurredAt: new Date(),
      dedupeKey: "k1",
    });

    expect(first).toBe(1);
    // The second must lose, and must not burn a seq on the way out.
    expect(second).toBeNull();

    const rows = await db().select().from(notification).where(eq(notification.userId, u.id));
    expect(rows).toHaveLength(1);

    const state = scalar(
      (await db().select().from(notificationState).where(eq(notificationState.userId, u.id)))[0],
    );
    expect(state.seq).toBe(1);
    expect(state.unread).toBe(1);
  });

  it("files rather than raises inside quiet hours", async () => {
    const u = await makeUser();
    await db().insert(notificationState).values({ userId: u.id }).onConflictDoNothing();
    await db()
      .update(notificationState)
      .set({ quietFromMinute: 0, quietToMinute: 1_439 })
      .where(eq(notificationState.userId, u.id));

    await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Payment",
      occurredAt: new Date(),
      dedupeKey: "quiet",
      localMinutes: 600,
    });

    const row = scalar((await db().select().from(notification))[0]);
    // Still written, still unread — just not allowed to interrupt.
    expect(row.alert).toBe(false);
    expect(row.readAt).toBeNull();
  });

  it("writes nothing at all when the master switch is off", async () => {
    const u = await makeUser();
    await db().insert(notificationState).values({ userId: u.id }).onConflictDoNothing();
    await db()
      .update(notificationState)
      .set({ enabled: false })
      .where(eq(notificationState.userId, u.id));

    const seq = await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Payment",
      occurredAt: new Date(),
      dedupeKey: "off",
    });

    expect(seq).toBeNull();
    expect(await db().select().from(notification)).toHaveLength(0);
  });
});

describe("the evaluator", () => {
  it("primes a new subscription instead of delivering back-history", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    await seedSubscriptions(db(), u.id, integrationId, "stripe");

    const subId = scalar(
      (
        await db()
          .select()
          .from(notificationSubscription)
          .where(eq(notificationSubscription.typeId, "metric_threshold_crossed"))
      )[0],
    ).id;
    await db()
      .update(notificationSubscription)
      .set({
        enabled: true,
        threshold: { metric: "mrr", comparator: "above", value: 1 },
      })
      .where(eq(notificationSubscription.id, subId));

    const subs = await db()
      .select()
      .from(notificationSubscription)
      .where(eq(notificationSubscription.id, subId));
    const row = scalar((await db().select().from(integrationTable))[0]);

    // A threshold this reading clears by miles. The first evaluation must still
    // say nothing: enabling a toggle is not a request for the past.
    await evaluate({
      db: db(),
      row,
      owner: { id: u.id, timezone: "UTC" },
      subs,
      metric: "mrr",
      result: series(),
    });

    expect(await db().select().from(notification)).toHaveLength(0);
    const cursor = scalar((await db().select().from(notificationCursor))[0]);
    expect(cursor.seenThrough).not.toBeNull();
  });

  it("fires a threshold on the edge and not again while it sits there", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const subId = id("nsub");
    await db()
      .insert(notificationSubscription)
      .values({
        id: subId,
        userId: u.id,
        integrationId,
        typeId: "metric_threshold_crossed",
        enabled: true,
        params: {},
        threshold: { metric: "mrr", comparator: "above", value: 500_000 },
        minIntervalSeconds: 60,
      });
    // Already primed, so this evaluation is allowed to speak.
    await db()
      .insert(notificationCursor)
      .values({ subscriptionId: subId, seenThrough: new Date(Date.now() - 86_400_000) });

    const subs = await db()
      .select()
      .from(notificationSubscription)
      .where(eq(notificationSubscription.id, subId));
    const row = scalar((await db().select().from(integrationTable))[0]);
    const args = {
      db: db(),
      row,
      owner: { id: u.id, timezone: "UTC" },
      subs,
      metric: "mrr",
      result: series(),
    };

    await evaluate(args);
    expect(await db().select().from(notification)).toHaveLength(1);

    // Still above the line, so still nothing new to say.
    await evaluate(args);
    expect(await db().select().from(notification)).toHaveLength(1);
  });

  it("says nothing for a threshold the user never configured", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const subId = id("nsub");
    await db().insert(notificationSubscription).values({
      id: subId,
      userId: u.id,
      integrationId,
      typeId: "metric_threshold_crossed",
      enabled: true,
      params: {},
      threshold: null,
      minIntervalSeconds: 60,
    });
    await db()
      .insert(notificationCursor)
      .values({ subscriptionId: subId, seenThrough: new Date(0) });

    await evaluate({
      db: db(),
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      subs: await db()
        .select()
        .from(notificationSubscription)
        .where(eq(notificationSubscription.id, subId)),
      metric: "mrr",
      result: series(),
    });

    expect(await db().select().from(notification)).toHaveLength(0);
  });

  it("ignores a failed fetch", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const subId = id("nsub");
    await db()
      .insert(notificationSubscription)
      .values({
        id: subId,
        userId: u.id,
        integrationId,
        typeId: "metric_threshold_crossed",
        enabled: true,
        params: {},
        threshold: { metric: "mrr", comparator: "above", value: 1 },
        minIntervalSeconds: 60,
      });

    await evaluate({
      db: db(),
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      subs: await db()
        .select()
        .from(notificationSubscription)
        .where(eq(notificationSubscription.id, subId)),
      metric: "mrr",
      result: {
        ok: false,
        integrationId,
        metric: "mrr",
        code: "rate_limited",
        message: "later",
        retryAfterSeconds: 30,
      } as never,
    });

    // A failed fetch is not a notification. The connection going *dead* is, and
    // that comes from the edge detector instead.
    expect(await db().select().from(notification)).toHaveLength(0);
  });
});

describe("event-sourced notifications", () => {
  /// A stub stream, so the `fetchEvents` path is proven without a real provider.
  function stubAdapter(events: RawEvent[], cursor: string | null = "c2") {
    return {
      fetchEvents: async (_ctx: unknown, _creds: unknown, request: { stream: string }) => {
        seen.push(request.stream);
        return { events, cursor };
      },
    };
  }
  let seen: string[] = [];
  beforeEach(() => {
    seen = [];
  });

  function event(id: string, type: string, minutesAgo: number, url: string | null = null) {
    return {
      id,
      type,
      t: new Date(Date.now() - minutesAgo * 60_000),
      title: `Event ${id}`,
      body: null,
      amount: null,
      currency: null,
      url,
    };
  }

  async function subscribe(userId: string, integrationId: string, typeId: string) {
    const subId = id("nsub");
    await db().insert(notificationSubscription).values({
      id: subId,
      userId,
      integrationId,
      typeId,
      enabled: true,
      params: {},
      threshold: null,
      minIntervalSeconds: 60,
    });
    return subId;
  }

  it("polls one stream once however many types read it", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    // Two types, one stream.
    const first = await subscribe(u.id, integrationId, "payment_failed");
    await subscribe(u.id, integrationId, "refund_issued");
    await db()
      .insert(notificationCursor)
      .values({ subscriptionId: first, seenThrough: new Date(Date.now() - 3_600_000) });

    await evaluateEvents({
      db: db(),
      ctx: {} as never,
      credentials: {},
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      subs: await db().select().from(notificationSubscription),
      adapter: stubAdapter([
        event("e1", "payment_failed", 10),
        event("e2", "refund_issued", 5),
      ]) as never,
    });

    // One poll, not one per toggle: a user with six types enabled on a stream
    // must not cost six provider calls a tick.
    expect(seen).toEqual(["charges"]);
    expect(await db().select().from(notification)).toHaveLength(2);
  });

  it("primes rather than delivering the backlog", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    await subscribe(u.id, integrationId, "payment_failed");

    await evaluateEvents({
      db: db(),
      ctx: {} as never,
      credentials: {},
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      subs: await db().select().from(notificationSubscription),
      adapter: stubAdapter([event("e1", "payment_failed", 10)]) as never,
    });

    // Turning a toggle on is not a request for the past. The cursor is written
    // to "now", so anything that already happened is history rather than news.
    expect(await db().select().from(notification)).toHaveLength(0);
    const cursor = scalar((await db().select().from(notificationCursor))[0]);
    expect(cursor.seenThrough).not.toBeNull();
  });

  it("delivers once, then dedupes the same event on replay", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const subId = await subscribe(u.id, integrationId, "payment_failed");
    // Already primed an hour ago, so this evaluation is allowed to speak.
    await db()
      .insert(notificationCursor)
      .values({ subscriptionId: subId, seenThrough: new Date(Date.now() - 3_600_000) });

    const args = {
      db: db(),
      ctx: {} as never,
      credentials: {},
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      adapter: stubAdapter([event("e1", "payment_failed", 10)]) as never,
    };

    await evaluateEvents({ ...args, subs: await db().select().from(notificationSubscription) });
    expect(await db().select().from(notification)).toHaveLength(1);

    // The same charge id on the next poll — which happens whenever the window
    // still covers it — must not arrive twice.
    await evaluateEvents({ ...args, subs: await db().select().from(notificationSubscription) });
    expect(await db().select().from(notification)).toHaveLength(1);
  });

  it("drops a link the provider's allowlist does not cover", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const subId = await subscribe(u.id, integrationId, "payment_failed");
    await db()
      .insert(notificationCursor)
      .values({ subscriptionId: subId, seenThrough: new Date(Date.now() - 3_600_000) });

    await evaluateEvents({
      db: db(),
      ctx: {} as never,
      credentials: {},
      row: scalar((await db().select().from(integrationTable))[0]),
      owner: { id: u.id, timezone: "UTC" },
      subs: await db().select().from(notificationSubscription),
      adapter: stubAdapter([
        event("e1", "payment_failed", 10, "https://evil.example.com/steal"),
      ]) as never,
    });

    // The Mac hands this to `NSWorkspace`, so an adapter is not trusted to
    // have checked it.
    expect(scalar((await db().select().from(notification))[0]).url).toBeNull();
  });
});

describe("connection_broken", () => {
  it("fires on the edge, not on the state", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);
    const row = {
      id: integrationId,
      provider: "stripe",
      label: "Acme Inc",
      accountLabel: null,
      userId: u.id,
    };

    await emitConnectionBroken(db(), "ok", row);
    expect(await db().select().from(notification)).toHaveLength(1);

    // A revoked key fails on every poll. Notifying on the state would mean one
    // of these every five minutes until somebody reconnects.
    await emitConnectionBroken(db(), "auth_failed", row);
    expect(await db().select().from(notification)).toHaveLength(1);
  });
});

describe("seeding", () => {
  it("never enables a threshold by default, and does not re-seed", async () => {
    const u = await makeUser();
    const integrationId = await makeIntegration(u.id);

    await seedSubscriptions(db(), u.id, integrationId, "stripe");
    const first = await db().select().from(notificationSubscription);
    expect(first.length).toBeGreaterThan(0);

    const threshold = scalar(first.find((r) => r.typeId === "metric_threshold_crossed"));
    // A bound only the user knows. Defaulting one on would fire on day one and
    // be wrong.
    expect(threshold.enabled).toBe(false);

    // Seeding twice must not duplicate, and must not resurrect a toggle the
    // user turned off.
    await db()
      .update(notificationSubscription)
      .set({ enabled: true })
      .where(eq(notificationSubscription.id, threshold.id));
    await seedSubscriptions(db(), u.id, integrationId, "stripe");

    const second = await db().select().from(notificationSubscription);
    expect(second).toHaveLength(first.length);
    expect(scalar(second.find((r) => r.id === threshold.id)).enabled).toBe(true);
  });
});

describe("routes", () => {
  it("pages forward and backward without losing the live cursor", async () => {
    const { user: u, token } = await signedInUser();
    const integrationId = await makeIntegration(u.id);
    for (let i = 0; i < 5; i++) {
      await emit(db(), {
        userId: u.id,
        integrationId,
        provider: "stripe",
        connectionLabel: "Acme",
        typeId: "payment_received",
        severity: "success",
        title: `Payment ${i}`,
        occurredAt: new Date(Date.now() - (5 - i) * 60_000),
        dedupeKey: `k${i}`,
      });
    }

    const page = (await (await call("/v1/notifications?limit=2", token)).json()) as FeedBody;
    expect(page.items).toHaveLength(2);
    expect(page.hasMore).toBe(true);
    // The highest seq that *exists*, not the highest returned — advancing the
    // live cursor from a page would mark unseen rows as seen.
    expect(page.seq).toBe(5);
    expect(page.oldestSeq).toBe(4);
    expect(page.items.map((i: { title: string }) => i.title)).toEqual(["Payment 4", "Payment 3"]);

    const older = (await (
      await call(`/v1/notifications?before=${page.oldestSeq}&limit=2`, token)
    ).json()) as FeedBody;
    expect(older.items.map((i: { title: string }) => i.title)).toEqual(["Payment 2", "Payment 1"]);
    expect(older.seq).toBe(5);
    // Scrolling back through history is not news, so it never suppresses banners.
    expect(older.truncated).toBe(false);
  });

  it("sorts on occurredAt even when seq disagrees with it", async () => {
    const { user: u, token } = await signedInUser();

    // Discovery order is not event order: a backfill can find an old payment
    // after a new one. `seq` ascends with discovery, `occurredAt` with the
    // event, and the feed has to honour the second.
    await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Recent",
      occurredAt: new Date("2026-10-05T12:00:00.000Z"),
      dedupeKey: "d1",
    });
    await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Older, found later",
      occurredAt: new Date("2026-10-01T12:00:00.000Z"),
      dedupeKey: "d2",
    });

    const page = (await (await call("/v1/notifications", token)).json()) as FeedBody;
    expect(page.items.map((i: { title: string }) => i.title)).toEqual([
      "Recent",
      "Older, found later",
    ]);
    // The cursor is still the higher seq, which is what makes the next
    // `?since=` correct even though it is the older event.
    expect(page.seq).toBe(2);
  });

  it("refuses since and before together", async () => {
    const { token } = await signedInUser();
    const res = await call("/v1/notifications?since=1&before=5", token);
    expect(res.status).toBe(400);
  });

  it("answers 404, not 403, for another user's connection", async () => {
    const { token } = await signedInUser();
    const other = await makeUser();
    const theirs = await makeIntegration(other.id);

    const res = await call(`/v1/notifications?integrationId=${theirs}`, token);
    // A 403 would confirm it exists.
    expect(res.status).toBe(404);
  });

  it("304s the cursor poll on a matching etag", async () => {
    const { user: u, token } = await signedInUser();
    await emit(db(), {
      userId: u.id,
      integrationId: null,
      provider: "stripe",
      connectionLabel: "Acme",
      typeId: "payment_received",
      severity: "success",
      title: "Payment",
      occurredAt: new Date(),
      dedupeKey: "c1",
    });

    const first = await call("/v1/notifications/cursor", token);
    expect(first.status).toBe(200);
    const etag = scalar(first.headers.get("etag") ?? undefined);
    expect(first.headers.get("x-notch-poll-after")).toBeTruthy();

    const second = await call("/v1/notifications/cursor", token, {
      headers: { "if-none-match": etag },
    });
    expect(second.status).toBe(304);
  });

  it("recomputes unread rather than decrementing it", async () => {
    const u = await makeUser();
    for (let i = 0; i < 3; i++) {
      await emit(db(), {
        userId: u.id,
        integrationId: null,
        provider: "stripe",
        connectionLabel: "Acme",
        typeId: "payment_received",
        severity: "success",
        title: `P${i}`,
        occurredAt: new Date(),
        dedupeKey: `r${i}`,
      });
    }

    // Deliberately drifted, as a double-decrement would leave it.
    await db()
      .update(notificationState)
      .set({ unread: 99 })
      .where(eq(notificationState.userId, u.id));

    const unread = await markRead(db(), u.id, { upToSeq: 2 });
    expect(unread).toBe(1);
  });

  it("409s a stale settings write and hands back the winner", async () => {
    const { user: u, token } = await signedInUser();
    await makeIntegration(u.id);

    const current = (await (
      await call("/v1/notifications/settings", token)
    ).json()) as SettingsBody;
    const res = await call("/v1/notifications/settings", token, {
      method: "PUT",
      body: JSON.stringify({ ...current, revision: current.revision + 7 }),
    });

    expect(res.status).toBe(409);
    const body = (await res.json()) as SettingsBody;
    expect(body.code).toBe("STALE_REVISION");
    expect(body.revision).toBe(current.revision);
  });

  it("will not let a settings write touch another account's subscription", async () => {
    const { token } = await signedInUser();
    const other = await makeUser();
    const theirs = await makeIntegration(other.id);
    await seedSubscriptions(db(), other.id, theirs, "stripe");
    const victim = scalar((await db().select().from(notificationSubscription))[0]);

    const current = (await (
      await call("/v1/notifications/settings", token)
    ).json()) as SettingsBody;
    const res = await call("/v1/notifications/settings", token, {
      method: "PUT",
      body: JSON.stringify({
        ...current,
        subscriptions: [
          {
            id: victim.id,
            integrationId: theirs,
            typeId: victim.typeId,
            enabled: true,
            params: {},
            threshold: null,
            minIntervalSeconds: 60,
          },
        ],
      }),
    });

    expect(res.status).toBe(200);
    const after = scalar(
      (
        await db()
          .select()
          .from(notificationSubscription)
          .where(eq(notificationSubscription.id, victim.id))
      )[0],
    );
    // Scoped by user id, so the foreign row is simply not matched.
    expect(after.enabled).toBe(false);
  });
});
