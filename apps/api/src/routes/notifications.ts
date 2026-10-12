import { Hono } from "hono";
import { and, eq } from "drizzle-orm";
import {
  NotificationFeedQuery,
  NotificationReadRequest,
  NotificationSettings,
} from "@notch/schemas";
import {
  integration as integrationTable,
  notificationState,
  notificationSubscription,
} from "@notch/db";
import { authenticate, rateLimited, requireAccess, type AppContext } from "../middleware.ts";
import { feed, markRead, readCursor, seedSubscriptions } from "../lib/notifications.ts";

/**
 * The notification centre.
 *
 * Unlike `/v1/widgets`, **the server is authoritative here.** The Mac holds a
 * cache of the toggles, not the truth, because the server is the evaluator — a
 * muted type it never generates is bytes never sent and a device wake never
 * taken, which is the whole battery argument for doing it this way.
 */
export const notifications = new Hono<AppContext>();

notifications.get(
  "/cursor",
  authenticate,
  /**
   * Deliberately no `rateLimited` and no `requireAccess`.
   *
   * `take()` is two D1 writes per call, which on a recurring poll would make
   * the rate limiter cost more than the feature it protects; abuse control for
   * this one route belongs in a Cloudflare zone rule instead. And a 402 on a
   * background poll is noise — an unentitled user gets `seq: 0` with an hour's
   * backoff and simply stops asking.
   */
  async (c) => {
    const cursor = await readCursor(c.get("db"), c.get("identity").userId);

    // Weak, because the body is regenerated rather than byte-stable. Both
    // numbers are in it: unread changes when a row is read, and seq when one
    // arrives, and the client cares about each independently.
    const etag = `W/"${cursor.seq}.${cursor.unread}"`;
    c.header("etag", etag);
    c.header("cache-control", "private, max-age=15");
    c.header("x-notch-poll-after", String(cursor.pollAfterSeconds));

    if (c.req.header("if-none-match") === etag) return c.body(null, 304);
    return c.json(cursor);
  },
);

notifications.get(
  "/",
  authenticate,
  requireAccess,
  rateLimited({ limit: 60, windowSeconds: 300 }),
  async (c) => {
    const db = c.get("db");
    const userId = c.get("identity").userId;

    const parsed = NotificationFeedQuery.safeParse({
      since: c.req.query("since"),
      before: c.req.query("before"),
      limit: c.req.query("limit"),
      integrationId: c.req.query("integrationId"),
    });
    if (!parsed.success) {
      return c.json({ code: "BAD_REQUEST", message: "Invalid feed query." }, 400);
    }

    // 404 rather than 403 for somebody else's connection: a 403 confirms it
    // exists.
    if (parsed.data.integrationId) {
      const [owned] = await db
        .select({ id: integrationTable.id })
        .from(integrationTable)
        .where(
          and(
            eq(integrationTable.id, parsed.data.integrationId),
            eq(integrationTable.userId, userId),
          ),
        )
        .limit(1);
      if (!owned) return c.json({ code: "NOT_FOUND", message: "No such integration." }, 404);
    }

    return c.json(await feed(db, userId, parsed.data));
  },
);

notifications.post(
  "/read",
  authenticate,
  rateLimited({ limit: 60, windowSeconds: 300 }),
  async (c) => {
    const body = NotificationReadRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) {
      return c.json({ code: "BAD_REQUEST", message: "Provide upToSeq or ids." }, 400);
    }
    const unread = await markRead(c.get("db"), c.get("identity").userId, body.data);
    return c.json({ unread });
  },
);

notifications.get("/settings", authenticate, requireAccess, async (c) => {
  const db = c.get("db");
  const userId = c.get("identity").userId;

  // Seeded on read as well as on connect, so connections that predate this
  // feature get their toggles the first time anybody looks.
  const owned = await db
    .select({
      id: integrationTable.id,
      provider: integrationTable.provider,
    })
    .from(integrationTable)
    .where(eq(integrationTable.userId, userId));

  for (const row of owned) {
    await seedSubscriptions(db, userId, row.id, row.provider);
  }

  return c.json(await settingsFor(db, userId));
});

notifications.put(
  "/settings",
  authenticate,
  requireAccess,
  rateLimited({ limit: 30, windowSeconds: 300 }),
  async (c) => {
    const db = c.get("db");
    const userId = c.get("identity").userId;

    const body = NotificationSettings.safeParse(await c.req.json().catch(() => null));
    if (!body.success) {
      return c.json({ code: "BAD_REQUEST", message: "Invalid settings." }, 400);
    }

    const current = await settingsFor(db, userId);
    if (body.data.revision !== current.revision) {
      // The winning state rides back, so the loser can merge rather than guess
      // — the same shape `widgets.put` uses.
      return c.json(
        { code: "STALE_REVISION", message: "Settings changed elsewhere.", ...current },
        409,
      );
    }

    await db
      .update(notificationState)
      .set({
        enabled: body.data.enabled,
        quietFromMinute: body.data.quietFromMinute,
        quietToMinute: body.data.quietToMinute,
        revision: current.revision + 1,
        updatedAt: new Date(),
      })
      .where(eq(notificationState.userId, userId));

    // Only the fields a user owns. `params` and `threshold` come from the
    // client, but the row's identity and its integration never do — otherwise
    // a PUT could attach a subscription to somebody else's connection.
    for (const sub of body.data.subscriptions) {
      await db
        .update(notificationSubscription)
        .set({
          enabled: sub.enabled,
          params: sub.params,
          threshold: sub.threshold,
          minIntervalSeconds: sub.minIntervalSeconds,
          updatedAt: new Date(),
        })
        .where(
          and(
            eq(notificationSubscription.id, sub.id),
            // Scoped to the caller, so an id from another account updates
            // nothing rather than erroring and confirming it exists.
            eq(notificationSubscription.userId, userId),
          ),
        );
    }

    return c.json(await settingsFor(db, userId));
  },
);

async function settingsFor(db: AppContext["Variables"]["db"], userId: string) {
  await db.insert(notificationState).values({ userId }).onConflictDoNothing();

  const [state] = await db
    .select()
    .from(notificationState)
    .where(eq(notificationState.userId, userId))
    .limit(1);

  const subs = await db
    .select()
    .from(notificationSubscription)
    .where(eq(notificationSubscription.userId, userId));

  return {
    revision: state?.revision ?? 0,
    enabled: state?.enabled ?? true,
    quietFromMinute: state?.quietFromMinute ?? null,
    quietToMinute: state?.quietToMinute ?? null,
    subscriptions: subs.map((s) => ({
      id: s.id,
      integrationId: s.integrationId,
      typeId: s.typeId as never,
      enabled: s.enabled,
      params: s.params ?? {},
      threshold: s.threshold as never,
      minIntervalSeconds: s.minIntervalSeconds,
    })),
  };
}
