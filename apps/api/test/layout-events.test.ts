import { describe, expect, it } from "vitest";
import { layoutEvents, type StoredWidget } from "../src/lib/layout-events.ts";
import type { Widget } from "@notch/schemas";

/** A stored row, with only the fields the diff reads. */
function stored(overrides: Partial<StoredWidget> = {}): StoredWidget {
  return {
    id: "wdg_1",
    kind: "provider_metric",
    appId: "stripe",
    metric: "mrr",
    customMetricId: null,
    title: null,
    ...overrides,
  };
}

/** An incoming widget. Only the diffed fields matter, so the rest is filler. */
function incoming(overrides: Partial<Widget> = {}): Widget {
  return {
    id: "wdg_1",
    kind: "provider_metric",
    appId: "stripe",
    integrationId: null,
    metric: "mrr",
    customMetricId: null,
    title: null,
    size: "2x1",
    col: 0,
    row: 0,
    position: 0,
    granularity: "day",
    range: "30d",
    params: {},
    link: null,
    chart: "sparkline",
    visible: true,
    ...overrides,
  } as Widget;
}

const base = { userId: "usr_1", revision: 3, rows: 2 };
const kinds = (events: ReturnType<typeof layoutEvents>) => events.map((e) => e.kind);

describe("what changed in a layout", () => {
  it("says nothing when a save only reorders", async () => {
    // The app saves on every drag, including the ones that end where they
    // started. A `layout_saved` per idle save would drown everything else.
    const before = [stored({ id: "wdg_1" }), stored({ id: "wdg_2", metric: "subscribers" })];
    const after = [
      incoming({ id: "wdg_2", metric: "subscribers", position: 0 }),
      incoming({ id: "wdg_1", position: 1 }),
    ];

    expect(layoutEvents({ ...base, before, after })).toEqual([]);
  });

  it("reports an added widget with the properties worth charting", () => {
    const events = layoutEvents({
      ...base,
      before: [],
      after: [incoming({ id: "wdg_9", appId: "github", metric: "stars", chart: "bars" })],
    });

    expect(kinds(events)).toEqual(["widget_added", "layout_saved"]);
    expect(events[0]).toMatchObject({
      kind: "widget_added",
      userId: "usr_1",
      appId: "github",
      metric: "stars",
      chart: "bars",
      widgetKind: "provider_metric",
    });
  });

  it("reports a removed widget", () => {
    const events = layoutEvents({
      ...base,
      before: [stored({ id: "wdg_9", appId: "github", metric: "stars" })],
      after: [],
    });

    expect(kinds(events)).toEqual(["widget_removed", "layout_saved"]);
    expect(events[0]).toMatchObject({ appId: "github", metric: "stars" });
  });

  it("carries the real totals on layout_saved", () => {
    const events = layoutEvents({
      ...base,
      before: [],
      after: [incoming({ id: "a" }), incoming({ id: "b", metric: "subscribers" })],
    });

    expect(events.at(-1)).toMatchObject({
      kind: "layout_saved",
      widgets: 2,
      rows: 2,
      revision: 3,
    });
  });

  it("ignores dividers, which are furniture and not a metric anybody chose", () => {
    const events = layoutEvents({
      ...base,
      before: [],
      after: [incoming({ id: "div_1", kind: "divider", metric: null })],
    });

    expect(events).toEqual([]);
  });

  it("reports a custom app once, however many tiles it has", () => {
    // Three GitHub-stars tiles pointed at three repositories is one custom app.
    const events = layoutEvents({
      ...base,
      before: [],
      after: [
        incoming({ id: "w1", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
        incoming({ id: "w2", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
      ],
    });

    expect(kinds(events).filter((k) => k === "custom_app_added")).toHaveLength(1);
  });

  it("names a custom app by the title the user typed", () => {
    const events = layoutEvents({
      ...base,
      before: [],
      after: [
        incoming({
          id: "w1",
          kind: "custom_metric",
          appId: "plausible",
          customMetricId: "plg_visitors",
          title: "  Plausible visitors  ",
        }),
      ],
    });

    const added = events.find((e) => e.kind === "custom_app_added");
    expect(added).toMatchObject({
      name: "Plausible visitors",
      appId: "plausible",
      customMetricId: "plg_visitors",
      // Filled in by the route, which is the only place that can afford the
      // lookup.
      email: null,
    });
  });

  it("falls back to an id when the tile has no title", () => {
    const events = layoutEvents({
      ...base,
      before: [],
      after: [
        incoming({ id: "w1", kind: "custom_metric", customMetricId: "plg_visitors", title: null }),
      ],
    });

    expect(events.find((e) => e.kind === "custom_app_added")).toMatchObject({
      name: "plg_visitors",
    });
  });

  it("does not report a custom app that was already there", () => {
    const before = [
      stored({ id: "w1", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
    ];
    const after = [
      incoming({ id: "w1", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
      incoming({ id: "w2", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
    ];

    const events = layoutEvents({ ...base, before, after });
    expect(kinds(events)).not.toContain("custom_app_added");
    // The second tile is still a widget somebody added.
    expect(kinds(events)).toContain("widget_added");
  });

  it("reports a custom app removed once when its last tile goes", () => {
    const before = [
      stored({ id: "w1", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
      stored({ id: "w2", kind: "custom_metric", customMetricId: "plg_v", title: "Visitors" }),
    ];

    const events = layoutEvents({ ...base, before, after: [] });
    expect(kinds(events).filter((k) => k === "custom_app_removed")).toHaveLength(1);
  });

  it("caps the events from a wholesale rebuild", () => {
    const after = Array.from({ length: 100 }, (_, i) => incoming({ id: `w${i}` }));
    const events = layoutEvents({ ...base, before: [], after });

    expect(kinds(events).filter((k) => k === "widget_added")).toHaveLength(40);
    // The totals are still honest, which is the point of keeping this event.
    expect(events.at(-1)).toMatchObject({ kind: "layout_saved", widgets: 100 });
  });
});
