import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { WidgetLayout } from "@notch/schemas";
import { widget as widgetTable, widgetRevision } from "@notch/db";
import { authenticate, type AppContext } from "../middleware.ts";
import type { Database } from "../lib/db.ts";

/**
 * The layout backup.
 *
 * The Mac is authoritative — `layout.json` on disk is the truth, and this is a
 * copy kept so a reinstall or a second machine has somewhere to start. The web
 * dashboard reads it and does not write it.
 *
 * `revision` exists only so two Macs cannot silently clobber one another. A 409
 * carries the winning state back, so the loser can merge rather than guess.
 */
export const widgets = new Hono<AppContext>();

widgets.use("*", authenticate);

interface LayoutMeta {
  revision: number;
  rows: number;
  display: "grid" | "list";
}

async function layoutMeta(db: Database, userId: string): Promise<LayoutMeta> {
  const [row] = await db
    .select()
    .from(widgetRevision)
    .where(eq(widgetRevision.userId, userId))
    .limit(1);
  return {
    revision: row?.revision ?? 0,
    rows: row?.rows ?? 2,
    display: (row?.display === "list" ? "list" : "grid") as "grid" | "list",
  };
}

widgets.get("/", async (c) => {
  const db = c.get("db");
  const userId = c.get("identity").userId;

  const rows = await db.select().from(widgetTable).where(eq(widgetTable.userId, userId));
  const meta = await layoutMeta(db, userId);

  return c.json({
    ...meta,
    widgets: rows
      .sort((a, b) => a.position - b.position)
      .map((r) => ({
        id: r.id,
        kind: r.kind,
        appId: r.appId,
        integrationId: r.integrationId,
        metric: r.metric,
        customMetricId: r.customMetricId,
        title: r.title,
        size: r.size,
        col: r.col,
        row: r.row,
        position: r.position,
        granularity: r.granularity,
        range: r.range,
        chart: r.chart,
        visible: r.visible,
      })),
  });
});

widgets.put("/", async (c) => {
  const body = WidgetLayout.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ code: "BAD_REQUEST", message: "Invalid layout." }, 400);

  const db = c.get("db");
  const userId = c.get("identity").userId;
  const meta = await layoutMeta(db, userId);

  if (body.data.revision !== meta.revision) {
    const rows = await db.select().from(widgetTable).where(eq(widgetTable.userId, userId));
    return c.json(
      {
        code: "STALE_REVISION",
        ...meta,
        widgets: rows.sort((a, b) => a.position - b.position),
      },
      409,
    );
  }

  // Whole-list replace. A notch layout is at most a dozen rows, and per-widget
  // PATCH would make a single drag into three round trips with a half-applied
  // state in between.
  await db.delete(widgetTable).where(eq(widgetTable.userId, userId));
  if (body.data.widgets.length > 0) {
    await db.insert(widgetTable).values(
      body.data.widgets.map((w, index) => ({
        id: w.id,
        userId,
        kind: w.kind,
        appId: w.appId,
        integrationId: w.integrationId,
        metric: w.metric,
        customMetricId: w.customMetricId,
        title: w.title,
        size: w.size,
        col: w.col,
        row: w.row,
        position: index,
        granularity: w.granularity,
        range: w.range,
        chart: w.chart,
        visible: w.visible,
      })),
    );
  }

  const next = meta.revision + 1;
  const { rows, display } = body.data;
  await db
    .insert(widgetRevision)
    .values({ userId, revision: next, rows, display })
    .onConflictDoUpdate({
      target: widgetRevision.userId,
      set: { revision: next, rows, display, updatedAt: new Date() },
    });

  return c.json({ revision: next, rows, display, widgets: body.data.widgets });
});
