import { and, eq, isNotNull } from "drizzle-orm";
import { widget as widgetTable } from "@notch/db";
import { Granularity, TimeRange } from "@notch/schemas";
import type { Database } from "./db.ts";
import { cacheKey } from "./metric-cache.ts";

/**
 * One number to keep warm: an exact cache key, not a metric name.
 *
 * The distinction is the entire reason this file exists. The cron used to warm
 * `(integration, metric)` at a hardcoded `30d`, while the notch reads
 * `(integration, metric, granularity, range)` — so a 90-day tile was warmed
 * never, a 30-day tile was warmed whether or not it existed, and the only
 * thing the warming reliably produced was provider calls.
 */
export interface WarmTarget {
  integrationId: string;
  metric: string;
  granularity: Granularity;
  range: TimeRange;
  params: Record<string, string>;
}

/**
 * What the notch will ask for next, from the widgets it has already told us
 * about.
 *
 * The layout is synced to `widget` for backup and for exactly this: the server
 * knows every visible tile, its metric, its granularity and its range, which
 * is the whole key. Nothing is inferred from what a *key can read* —
 * `integration.enabledMetrics` is "every metric this scope allows", which for
 * a payments key is five metrics whether or not a single tile shows one.
 *
 * Hidden widgets are left out: they are not on screen, so nothing reads them.
 */
export async function widgetWarmTargets(db: Database): Promise<Map<string, WarmTarget[]>> {
  const rows = await db
    .select({
      integrationId: widgetTable.integrationId,
      metric: widgetTable.metric,
      granularity: widgetTable.granularity,
      range: widgetTable.range,
      position: widgetTable.position,
    })
    .from(widgetTable)
    .where(
      and(
        eq(widgetTable.visible, true),
        isNotNull(widgetTable.integrationId),
        isNotNull(widgetTable.metric),
      ),
    )
    .orderBy(widgetTable.position);

  const byIntegration = new Map<string, WarmTarget[]>();
  const seen = new Set<string>();

  for (const row of rows) {
    if (!row.integrationId || !row.metric) continue;

    // A widget stores its granularity and range as text; a row written by an
    // older app — or by hand — can hold something this build does not know.
    // Skipping beats warming a key the reader will never produce.
    const granularity = Granularity.safeParse(row.granularity);
    const range = TimeRange.safeParse(row.range);
    if (!granularity.success || !range.success) continue;

    const target: WarmTarget = {
      integrationId: row.integrationId,
      metric: row.metric,
      granularity: granularity.data,
      range: range.data,
      // Widget params live in the app's own layout, not in this table, so a
      // metric that requires one is not warmable from here. The caller drops
      // those; see `widgetScoped` in the cron.
      params: {},
    };

    // Two tiles on the same metric and range are one number. Deduped here
    // rather than relying on the single-flight map downstream, so the
    // per-integration budget counts numbers rather than tiles.
    const key = cacheKey(target, target.granularity);
    if (seen.has(key)) continue;
    seen.add(key);

    const list = byIntegration.get(row.integrationId);
    if (list) list.push(target);
    else byIntegration.set(row.integrationId, [target]);
  }

  return byIntegration;
}
