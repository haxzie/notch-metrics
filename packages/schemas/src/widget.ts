import { z } from "zod";
import { Granularity, TimeRange } from "./money.ts";
import { AppId, IntegrationId, MetricId, PluginId, WidgetId } from "./ids.ts";

export const WidgetKind = z.enum(["provider_metric", "custom_metric", "divider"]);
export type WidgetKind = z.infer<typeof WidgetKind>;

export const ChartKind = z.enum(["none", "sparkline", "bars"]);
export type ChartKind = z.infer<typeof ChartKind>;

/**
 * Widget sizes on the notch's six-column grid.
 *
 * Six columns, not eight, so three tiles sit across the notch at two columns
 * each — which is the layout the design calls for and the one a headline
 * figure like "$55,678" actually fits in.
 *
 * `"<cols>x<rows>"`, any span that fits the grid.
 *
 * This used to be a closed enum of four presets, which is why resizing a
 * widget was a button that cycled through them — there was nothing else it
 * could do. Dragging a handle needs every size in between to exist. The
 * encoding is unchanged, so an old `layout.json` or a `PUT /v1/widgets` from
 * a previous build still parses; only the accepted set is wider.
 */
export const WidgetSize = z.string().regex(/^[1-6]x[1-4]$/, "A widget size looks like 2x1.");
export type WidgetSize = z.infer<typeof WidgetSize>;

/** The presets the UI offers in one click. Every span is reachable by drag. */
export const WIDGET_SIZE_PRESETS = ["1x1", "2x1", "2x2", "6x2"] as const;

export function widgetSizeCells(size: WidgetSize): { cols: number; rows: number } {
  const [cols, rows] = size.split("x").map(Number);
  return { cols: cols ?? 2, rows: rows ?? 1 };
}

export const GRID_COLUMNS = 6;

/**
 * How tall the notch opens, in grid rows.
 *
 * Not a constant: the handle on the bottom edge drags rows in and out. Bounded
 * because a notch taller than this stops being a glanceable overlay and
 * becomes a window.
 */
export const GRID_DEFAULT_ROWS = 2;
export const GRID_MIN_ROWS = 1;
export const GRID_MAX_ROWS = 4;

/**
 * Grid of tiles, or a list of rows grouped by app.
 *
 * The list is not a lesser view: it is the one that fits a dozen numbers from
 * four apps into a notch, where the grid tops out at six tiles and starts
 * hiding things.
 */
export const DisplayMode = z.enum(["grid", "list"]);
export type DisplayMode = z.infer<typeof DisplayMode>;

export const Widget = z.object({
  id: WidgetId,
  kind: WidgetKind,

  /**
   * The app this number comes from — "stripe", "google-analytics", a custom
   * metric's own declared app, or "unknown".
   *
   * Stored on the widget rather than looked up through `integrationId`,
   * because a widget whose integration has been disconnected still has to
   * render: it becomes a "reconnect Stripe" tile, and it cannot say *which*
   * app to reconnect if the only link was the row that was just deleted.
   */
  appId: AppId.default("unknown"),

  /** Null for custom and divider widgets. */
  integrationId: IntegrationId.nullable(),
  metric: MetricId.nullable(),
  /** Set only for `custom_metric`; resolves to a local plugin directory. */
  customMetricId: PluginId.nullable(),
  title: z.string().max(60).nullable(),
  size: WidgetSize.default("2x1"),
  col: z
    .number()
    .int()
    .min(0)
    .max(GRID_COLUMNS - 1),
  row: z
    .number()
    .int()
    .min(0)
    .max(GRID_MAX_ROWS - 1),
  position: z.number().int().min(0),
  granularity: Granularity.default("day"),
  range: TimeRange.default("30d"),
  chart: ChartKind.default("sparkline"),
  visible: z.boolean().default(true),
});
export type Widget = z.infer<typeof Widget>;

/**
 * The layout backup.
 *
 * The Mac is authoritative — `layout.json` on disk is the truth and this is a
 * copy kept so a reinstall or a second machine has somewhere to start. The
 * `revision` exists only so two Macs cannot silently clobber each other; a 409
 * carries the winning state back so the loser can merge rather than guess.
 */
export const WidgetLayout = z.object({
  revision: z.number().int().min(0),
  rows: z.number().int().min(GRID_MIN_ROWS).max(GRID_MAX_ROWS).default(GRID_DEFAULT_ROWS),
  display: DisplayMode.default("grid"),
  widgets: z.array(Widget),
});
export type WidgetLayout = z.infer<typeof WidgetLayout>;

export const WidgetLayoutConflict = z.object({
  code: z.literal("STALE_REVISION"),
  revision: z.number().int(),
  rows: z.number().int(),
  display: DisplayMode,
  widgets: z.array(Widget),
});
export type WidgetLayoutConflict = z.infer<typeof WidgetLayoutConflict>;
