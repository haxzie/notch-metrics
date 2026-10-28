import type { Widget } from "@notch/schemas";
import type { ProductEvent } from "./track.ts";

/**
 * What changed in a notch layout, as product events.
 *
 * Pure, and separate from the route, because this is the only part of the
 * widget surface with a judgement in it: `PUT /v1/widgets` replaces the whole
 * list and says nothing about intent, so every statement about what the user
 * *did* is inferred from two lists of rows. That inference deserves tests that
 * do not need a database.
 */

/** The subset of a stored row this needs. Keeps the D1 row type out of here. */
export interface StoredWidget {
  id: string;
  kind: string;
  appId: string;
  metric: string | null;
  customMetricId: string | null;
  title: string | null;
}

/**
 * The most widget events one save may produce.
 *
 * Somebody who clears their notch and rebuilds it in one PUT would otherwise
 * emit an event per tile twice over. The cap is well above a full layout
 * (`GRID_MAX_ROWS` × `GRID_COLUMNS`), so it only ever truncates the pathological
 * case, and `layout_saved` carries the real totals either way.
 */
const MAX_WIDGET_EVENTS = 40;

/**
 * A custom metric's identity, for deciding whether it is new to this layout.
 *
 * Keyed on the plugin id where there is one, because that is what the user
 * registered; `appId` is the fallback for a custom widget written before
 * plugin ids existed, and the two never collide because one is prefixed.
 */
function customKey(widget: { appId: string; customMetricId: string | null }): string {
  return widget.customMetricId ?? widget.appId;
}

/**
 * What to call a custom app in Slack.
 *
 * The widget title first: it is what the user typed, and it is the only
 * human-written string available. Falling back to the ids keeps the message
 * readable rather than empty for an untitled tile.
 */
function customName(widget: {
  title: string | null;
  appId: string;
  customMetricId: string | null;
}): string {
  const title = widget.title?.trim();
  if (title) return title;
  return widget.customMetricId ?? widget.appId;
}

export function layoutEvents(input: {
  userId: string;
  revision: number;
  rows: number;
  before: StoredWidget[];
  after: Widget[];
}): ProductEvent[] {
  const { userId, before, after } = input;
  const events: ProductEvent[] = [];

  const beforeIds = new Set(before.map((w) => w.id));
  const afterIds = new Set(after.map((w) => w.id));

  // Dividers are layout furniture, not a metric anybody chose. Counting them
  // as widgets added would make the number mean two different things.
  const added = after.filter((w) => !beforeIds.has(w.id) && w.kind !== "divider");
  const removed = before.filter((w) => !afterIds.has(w.id) && w.kind !== "divider");

  for (const w of added.slice(0, MAX_WIDGET_EVENTS)) {
    events.push({
      kind: "widget_added",
      userId,
      widgetKind: w.kind,
      appId: w.appId,
      metric: w.metric,
      size: w.size,
      chart: w.chart,
      range: w.range,
    });
  }
  for (const w of removed.slice(0, MAX_WIDGET_EVENTS)) {
    events.push({
      kind: "widget_removed",
      userId,
      widgetKind: w.kind,
      appId: w.appId,
      metric: w.metric,
    });
  }

  // A custom app counts as added when its *first* tile appears and removed
  // when its last one goes, not once per tile. Somebody with three GitHub-stars
  // tiles pointed at three repositories added one custom app.
  const customBefore = new Set(
    before.filter((w) => w.kind === "custom_metric").map((w) => customKey(w)),
  );
  const customAfter = new Map(
    after.filter((w) => w.kind === "custom_metric").map((w) => [customKey(w), w] as const),
  );

  for (const [key, widget] of customAfter) {
    if (customBefore.has(key)) continue;
    events.push({
      kind: "custom_app_added",
      userId,
      // Filled in by the caller, which is the only place that can afford the
      // lookup, and only when this event exists.
      email: null,
      appId: widget.appId,
      name: customName(widget),
      customMetricId: widget.customMetricId,
    });
  }
  for (const widget of before) {
    if (widget.kind !== "custom_metric") continue;
    const key = customKey(widget);
    if (customAfter.has(key)) continue;
    // Guards the duplicate: a user with two tiles for one custom app that both
    // go in the same save must produce one removal, not two.
    if (
      events.some(
        (e) =>
          e.kind === "custom_app_removed" &&
          e.customMetricId === widget.customMetricId &&
          e.appId === widget.appId,
      )
    ) {
      continue;
    }
    events.push({
      kind: "custom_app_removed",
      userId,
      email: null,
      appId: widget.appId,
      name: customName(widget),
      customMetricId: widget.customMetricId,
    });
  }

  // Only when something actually changed. The app saves the layout on every
  // drag, including the ones that end where they started, and a `layout_saved`
  // per idle save would drown the events above in the same dataset.
  if (events.length > 0) {
    events.push({
      kind: "layout_saved",
      userId,
      widgets: after.length,
      rows: input.rows,
      revision: input.revision,
    });
  }

  return events;
}
