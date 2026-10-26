import { describe, expect, it } from "vitest";
import { LocalMetricDescriptor, createApp, createMetric } from "../src/index.ts";

/**
 * The authoring API.
 *
 * What it replaces was two halves of one idea held apart: a metric declared
 * in `manifest.json` and answered inside a single `fetchMetric` that opened
 * with a chain of `if (request.metric === ...)`. These tests pin the two
 * properties that made it worth changing. A descriptor is derived from what
 * the author typed, so the id cannot be spelled two ways, and a mistake is
 * thrown at load rather than drawn as a tile that never fills.
 */
const fetch = async () => ({ value: 1 });

describe("createMetric", () => {
  it("produces a descriptor the wire schema accepts", () => {
    const metric = createMetric({
      id: "downloads",
      label: "Downloads",
      unit: "count",
      series: { granularities: ["day"] },
      methodology: "Downloads reported by the registry for the window.",
      fetch,
    });

    // The real validator, not a shape assertion. This descriptor goes into
    // the same manifest a hand-written one does, so it has to pass the same
    // gate or the API is generating files the app will refuse.
    expect(LocalMetricDescriptor.safeParse(metric.descriptor).success).toBe(true);
    expect(metric.descriptor.shape).toEqual({
      kind: "series",
      granularities: ["day"],
      compare: true,
    });
  });

  it("falls back to the label when no short label is given", () => {
    // Not truncated. A cut-off label is the one thing `shortLabel` exists to
    // avoid, so a label too long for a tile is the author's to fix and the
    // validator's to refuse.
    const metric = createMetric({
      id: "mrr",
      label: "MRR",
      unit: "currency",
      scalar: true,
      methodology: "Monthly recurring revenue.",
      fetch,
    });
    expect(metric.descriptor.shortLabel).toBe("MRR");
  });

  it("turns each kind into the shape the app speaks", () => {
    const kind = (definition: Record<string, unknown>) =>
      createMetric({
        id: "m",
        label: "M",
        unit: "count",
        methodology: "m",
        fetch,
        ...definition,
      } as Parameters<typeof createMetric>[0]).descriptor.shape;

    expect(kind({ scalar: true })).toEqual({ kind: "scalar" });
    expect(kind({ list: true })).toEqual({ kind: "list", limit: 10 });
    expect(kind({ list: { limit: 6 } })).toEqual({ kind: "list", limit: 6 });
    expect(kind({ total: { granularities: ["month"], compare: false } })).toEqual({
      kind: "total",
      granularities: ["month"],
      compare: false,
    });
  });

  it("refuses a metric that declares no kind", () => {
    expect(() =>
      createMetric({
        id: "nameless",
        label: "Nameless",
        unit: "count",
        methodology: "m",
        fetch,
      } as Parameters<typeof createMetric>[0]),
    ).toThrow(/declares no kind/);
  });

  it("refuses a metric with no fetch", () => {
    expect(() =>
      createMetric({
        id: "lazy",
        label: "Lazy",
        unit: "count",
        scalar: true,
        methodology: "m",
      } as unknown as Parameters<typeof createMetric>[0]),
    ).toThrow(/no fetch/);
  });
});

describe("createApp", () => {
  const metric = (id: string) =>
    createMetric({ id, label: id, unit: "count", scalar: true, methodology: "m", fetch });

  const app = (over: Record<string, unknown> = {}) =>
    createApp({
      id: "my-app",
      name: "My app",
      description: "d",
      allowedHosts: ["api.example.com"],
      metrics: [metric("a")],
      ...over,
    } as Parameters<typeof createApp>[0]);

  it("keys metrics by id so the runner can route one request", () => {
    const built = app({ metrics: [metric("a"), metric("b")] });
    expect(Object.keys(built.metrics)).toEqual(["a", "b"]);
    expect(built.describe().map((d) => d.id)).toEqual(["a", "b"]);
  });

  it("derives a manifest the app will accept", () => {
    // The whole point of generating it: this is the file `notch-metrics
    // build` writes, and it has to pass the same validator a hand-written
    // one did.
    const { manifest } = app();
    expect(manifest.entry).toBe("connector.mjs");
    expect(manifest.metrics.map((m) => m.id)).toEqual(["a"]);
    expect(manifest.allowedHosts).toEqual(["api.example.com"]);
  });

  it("derives authMode from the fields rather than asking", () => {
    // Declaring `none` while listing fields is a contradiction that used to
    // be writable, and it showed a form the app never read.
    expect(app().manifest.authMode).toBe("none");
    expect(
      app({ auth: [{ key: "api_key", label: "API key", type: "secret" }] }).manifest.authMode,
    ).toBe("api_key");
  });

  it("refuses two metrics under one id", () => {
    // Silently, one of them never runs, and which one depends on array
    // order. That is a wrong number rather than an error.
    expect(() => app({ metrics: [metric("a"), metric("a")] })).toThrow(/share the id "a"/);
  });

  it("refuses an app with no metrics", () => {
    expect(() => app({ metrics: [] })).toThrow(/at least one metric/);
  });

  it("refuses a host that is not a host", () => {
    // `allowedHosts` is the containment boundary, so a typo here is the one
    // field where a forgiving parse would be dangerous.
    expect(() => app({ allowedHosts: ["https://api.example.com/v1"] })).toThrow();
  });

  it("makes verify optional", () => {
    // An app against a public API has nothing to verify, and making every
    // one of those write an empty function was noise.
    expect(app().verify).toBeUndefined();
  });
});

/**
 * What a mistake looks like.
 *
 * The validation was always there: `createApp` parsed the manifest it built,
 * so a bad field did fail the build. What came out was the raw `ZodError`
 * array, which named `metrics.0.params.0.type` and buried the one useful
 * sentence in JSON. A connector author is usually an agent or somebody doing
 * this for the first time, and neither reads that and knows which line to
 * change.
 *
 * These assert the message, because the message is the feature.
 */
describe("what a mistake says", () => {
  const good = {
    id: "ok",
    label: "Ok",
    unit: "count",
    scalar: true,
    methodology: "m",
    fetch: async () => ({ value: 1 }),
  } as const;

  function failure(over: Record<string, unknown>): string {
    try {
      createMetric({ ...good, ...over } as Parameters<typeof createMetric>[0]);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
    throw new Error("expected createMetric to throw");
  }

  it("names the metric, not a position in an array", () => {
    const message = failure({ id: "Bad Id" });
    expect(message).toContain('Metric "Bad Id"');
    expect(message).toContain("id:");
    // The old message was a JSON blob. If this ever passes, the formatter
    // has been bypassed.
    expect(message).not.toContain('"code":');
  });

  it("lists every problem at once", () => {
    // One field at a time, with a rebuild between each, is the experience
    // this exists to avoid.
    const message = failure({
      id: "Bad Id",
      methodology: "",
      params: [{ key: "p", label: "P", type: "text" }],
    });
    expect(message).toContain("id:");
    expect(message).toContain("methodology:");
    expect(message).toContain("params.0.type:");
  });

  it("catches a label too long to be a short label", () => {
    // The fallback is the label itself, so a long one fails here rather than
    // being silently truncated into the cut-off text `shortLabel` exists to
    // avoid.
    expect(failure({ label: "A label far too long for a notch tile" })).toContain("shortLabel:");
  });

  it("catches a host that is a URL", () => {
    // `allowedHosts` is the containment boundary, so this is the field where
    // a forgiving parse would be dangerous rather than convenient.
    let message = "";
    try {
      createApp({
        id: "a",
        name: "A",
        description: "d",
        allowedHosts: ["https://api.example.com/v1"],
        metrics: [createMetric(good)],
      });
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }
    expect(message).toContain('App "a"');
    expect(message).toContain("allowedHosts");
  });
});
