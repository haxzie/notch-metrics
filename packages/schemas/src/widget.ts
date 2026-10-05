import { z } from "zod";
import { Granularity, TimeRange } from "./money.ts";
import { IntegrationId, MetricId, PluginId, WidgetId } from "./ids.ts";

export const WidgetKind = z.enum(["provider_metric", "custom_metric", "divider"]);
export type WidgetKind = z.infer<typeof WidgetKind>;

export const ChartKind = z.enum(["none", "sparkline", "bars"]);
export type ChartKind = z.infer<typeof ChartKind>;

/**
 * Widget sizes on the notch's 8x2 grid.
 *
 * `4x2` is the full-width hero — one big chart filling the expanded notch.
 * A closed enum rather than free integers so the packer has a finite set of
 * shapes to reason about and resize can snap rather than clamp.
 */
export const WidgetSize = z.enum(["1x1", "2x1", "2x2", "4x2"]);
export type WidgetSize = z.infer<typeof WidgetSize>;

export const GRID_COLUMNS = 8;
export const GRID_ROWS = 2;

export const WIDGET_SIZE_CELLS: Record<WidgetSize, { cols: number; rows: number }> = {
  "1x1": { cols: 1, rows: 1 },
  "2x1": { cols: 2, rows: 1 },
  "2x2": { cols: 2, rows: 2 },
  "4x2": { cols: 4, rows: 2 },
};

export const Widget = z.object({
  id: WidgetId,
  kind: WidgetKind,
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
    .max(GRID_ROWS - 1),
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
  widgets: z.array(Widget),
});
export type WidgetLayout = z.infer<typeof WidgetLayout>;

export const WidgetLayoutConflict = z.object({
  code: z.literal("STALE_REVISION"),
  revision: z.number().int(),
  widgets: z.array(Widget),
});
export type WidgetLayoutConflict = z.infer<typeof WidgetLayoutConflict>;
