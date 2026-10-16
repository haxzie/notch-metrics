import { describe, expect, it } from "vitest";
import { fieldsFromMessage, ingestUrl, toAxiomEvents } from "../src/index.ts";

const TRACE_TIME = Date.UTC(2026, 9, 16, 2, 49, 3);

describe("turning a console line into fields", () => {
  /**
   * The whole reason this Worker exists rather than a Logpush job. `logError`
   * and `logInfo` emit one JSON object, and its keys have to become columns —
   * otherwise `scope:"oauth.refresh.int_abc"` is a regex over a string.
   */
  it("lifts a structured line's keys to the top level", () => {
    const fields = fieldsFromMessage([
      JSON.stringify({ level: "error", scope: "oauth.refresh.int_abc", subsystem: "oauth" }),
    ]);
    expect(fields).toEqual({
      level: "error",
      scope: "oauth.refresh.int_abc",
      subsystem: "oauth",
    });
  });

  it("keeps the sweep counts as numbers, not a sentence", () => {
    const fields = fieldsFromMessage([
      JSON.stringify({ scope: "cron.tokenRefresh", candidates: 3, refreshed: 2, failed: 1 }),
    ]);
    expect(fields.refreshed).toBe(2);
    expect(fields.failed).toBe(1);
  });

  /** A stray line from a dependency is still evidence; it must not be dropped. */
  it("keeps an unstructured line as a message", () => {
    expect(fieldsFromMessage(["something happened"])).toEqual({ message: "something happened" });
  });

  it("joins several console arguments rather than losing all but the first", () => {
    expect(fieldsFromMessage(["[github]", { repo: "a/b" }])).toEqual({
      message: '[github] {"repo":"a/b"}',
    });
  });

  it("does not mistake a JSON array or a bare number for an object of fields", () => {
    expect(fieldsFromMessage(["[1,2,3]"])).toEqual({ message: "[1,2,3]" });
    expect(fieldsFromMessage(["42"])).toEqual({ message: "42" });
  });

  it("survives an object it cannot serialise", () => {
    const circular: Record<string, unknown> = {};
    circular.self = circular;
    expect(() => fieldsFromMessage(["prefix", circular])).not.toThrow();
  });
});

describe("flattening a batch of trace events", () => {
  it("writes one event per log line, carrying the producer and outcome", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api",
        outcome: "ok",
        eventTimestamp: TRACE_TIME,
        logs: [
          { timestamp: TRACE_TIME, level: "error", message: [JSON.stringify({ scope: "a" })] },
          { timestamp: TRACE_TIME, level: "info", message: [JSON.stringify({ scope: "b" })] },
        ],
        exceptions: [],
      },
    ]);

    const logs = events.filter((e) => e.kind === "log");
    expect(logs).toHaveLength(2);
    expect(logs.map((e) => e.scope)).toEqual(["a", "b"]);
    expect(logs.every((e) => e.worker === "notch-api" && e.outcome === "ok")).toBe(true);
    expect(logs[0]?._time).toBe(new Date(TRACE_TIME).toISOString());
  });

  it("records an exception workerd caught, which we never logged ourselves", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api",
        outcome: "exception",
        eventTimestamp: TRACE_TIME,
        logs: [],
        exceptions: [{ timestamp: TRACE_TIME, name: "TypeError", message: "x is not a function" }],
      },
    ]);

    const thrown = events.find((e) => e.kind === "exception");
    expect(thrown).toMatchObject({
      error: "TypeError",
      message: "x is not a function",
      level: "error",
      outcome: "exception",
    });
  });

  /**
   * The row that survives an invocation killed before it could log anything.
   * Without it an `exceededCpu` tick is simply absent, which reads as a tick
   * that never happened.
   */
  it("always emits an invocation row, even for a silent one", () => {
    const events = toAxiomEvents([
      { scriptName: "notch-api", outcome: "exceededCpu", eventTimestamp: TRACE_TIME },
    ]);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: "invocation", outcome: "exceededCpu" });
  });

  it("stamps an event with no timestamp rather than leaving it to ingest time", () => {
    const events = toAxiomEvents([{ scriptName: "notch-api", eventTimestamp: null }]);
    expect(Date.parse(String(events[0]?._time))).not.toBeNaN();
  });

  it("bounds a single enormous message", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api",
        eventTimestamp: TRACE_TIME,
        logs: [{ timestamp: TRACE_TIME, level: "error", message: ["x".repeat(50_000)] }],
      },
    ]);
    expect(String(events[0]?.message).length).toBeLessThan(10_000);
  });

  it("handles an empty batch without inventing anything", () => {
    expect(toAxiomEvents([])).toEqual([]);
  });
});

describe("the ingest endpoint", () => {
  /**
   * This shipped wrong once. `/v1/ingest/<name>` is what an Axiom overview
   * page shows; the API serves `/v1/datasets/<name>/ingest` and answers the
   * other with `404 path ... was not found` — which reads like a missing
   * dataset, not a wrong URL. Nothing else fails: the Worker runs, the
   * events are built, and the dataset simply stays empty.
   */
  it("uses the datasets path Axiom actually serves", () => {
    expect(ingestUrl({ AXIOM_DATASET: "notch-api" })).toBe(
      "https://api.axiom.co/v1/datasets/notch-api/ingest",
    );
  });

  it("honours an EU host", () => {
    expect(
      ingestUrl({ AXIOM_DATASET: "notch-api", AXIOM_API_URL: "https://api.eu.axiom.co" }),
    ).toBe("https://api.eu.axiom.co/v1/datasets/notch-api/ingest");
  });

  it("does not produce a double slash from a trailing one", () => {
    expect(ingestUrl({ AXIOM_DATASET: "d", AXIOM_API_URL: "https://api.axiom.co/" })).toBe(
      "https://api.axiom.co/v1/datasets/d/ingest",
    );
  });
});
