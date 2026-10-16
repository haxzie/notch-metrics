import { describe, expect, it } from "vitest";
import { fieldsFromMessage, ingestUrl, safePath, toAxiomEvents } from "../src/index.ts";

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

describe("the HTTP log, and what must never reach it", () => {
  /**
   * A connect link is `/connect/<randomToken(32)>` — a single-use credential
   * that completes somebody's OAuth flow. Axiom keeps events for thirty
   * days, which is far longer than the token is meant to live, so this is
   * the one thing in a path that absolutely cannot be shipped.
   */
  it("masks a connect token out of the path", () => {
    const token = "s1Ft-9xQmA_bC3dEfGhIjKlMnOpQrStUvWxYz012345";
    expect(safePath(`https://notchmetrics.com/connect/${token}`)).toBe("/connect/:x");
  });

  it("masks one of our own ids", () => {
    expect(safePath("https://api.notchmetrics.com/v1/integrations/int_k36otynw2pmm7gzz")).toBe(
      "/v1/integrations/:x",
    );
  });

  /** An OAuth callback carries `code` and `state`; the query goes entirely. */
  it("drops the query string", () => {
    expect(safePath("https://api.notchmetrics.com/v1/link/callback?code=abc&state=xyz")).toBe(
      "/v1/link/callback",
    );
  });

  /** The reason to want paths at all: which marketing pages are being read. */
  it("keeps a blog slug and a static file", () => {
    expect(safePath("https://notchmetrics.com/blog/how-to-track-stripe-mrr")).toBe(
      "/blog/how-to-track-stripe-mrr",
    );
    expect(safePath("https://notchmetrics.com/llms.txt")).toBe("/llms.txt");
  });

  it("masks anything with uppercase or unusual length, and survives a bad url", () => {
    expect(safePath("https://notchmetrics.com/AbCdEf")).toBe("/:x");
    expect(safePath(`https://notchmetrics.com/${"a".repeat(40)}`)).toBe("/:x");
    expect(safePath("not a url")).toBeNull();
    expect(safePath(undefined)).toBeNull();
  });

  it("puts method, path and status on the invocation row", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-web-production",
        outcome: "ok",
        eventTimestamp: TRACE_TIME,
        event: {
          request: { url: "https://notchmetrics.com/pricing?utm_source=x", method: "GET" },
          response: { status: 200 },
        },
      },
    ]);
    expect(events[0]).toMatchObject({
      kind: "invocation",
      method: "GET",
      path: "/pricing",
      status: 200,
      worker: "notch-web-production",
    });
  });

  it("leaves the HTTP fields off a cron tick, which has no request", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api-production",
        outcome: "ok",
        eventTimestamp: TRACE_TIME,
        event: null,
      },
    ]);
    expect(events[0]).not.toHaveProperty("method");
    expect(events[0]).not.toHaveProperty("path");
  });
});

describe("joining the two halves of one request", () => {
  /**
   * The gap this closes: a 402 on `/v1/metrics/batch` showed `method`,
   * `path`, `status` and nothing else, so "whose request was that?" could
   * only be answered by guessing from a timestamp. Both events come from the
   * same invocation, so the id and the caller are already in hand.
   */
  it("copies the request id and caller onto the invocation row", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api-production",
        outcome: "ok",
        eventTimestamp: TRACE_TIME,
        event: {
          request: { url: "https://api.notchmetrics.com/v1/metrics/batch", method: "POST" },
          response: { status: 402 },
        },
        logs: [
          {
            timestamp: TRACE_TIME,
            level: "info",
            message: [
              JSON.stringify({
                scope: "http",
                requestId: "a4b63-LHR",
                userId: "usr_abc",
                plan: "trial",
                route: "/v1/metrics/batch",
                status: 402,
              }),
            ],
          },
        ],
      },
    ]);

    const invocation = events.find((e) => e.kind === "invocation");
    expect(invocation).toMatchObject({
      requestId: "a4b63-LHR",
      userId: "usr_abc",
      plan: "trial",
      status: 402,
      method: "POST",
    });
  });

  it("copies it onto an exception too, which is where it matters most", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api-production",
        outcome: "exception",
        eventTimestamp: TRACE_TIME,
        logs: [
          {
            timestamp: TRACE_TIME,
            level: "info",
            message: [JSON.stringify({ scope: "http", requestId: "r-9", userId: "usr_x" })],
          },
        ],
        exceptions: [{ timestamp: TRACE_TIME, name: "TypeError", message: "boom" }],
      },
    ]);

    expect(events.find((e) => e.kind === "exception")).toMatchObject({
      requestId: "r-9",
      userId: "usr_x",
      error: "TypeError",
    });
  });

  it("adds nothing to a cron tick, which has no request behind it", () => {
    const events = toAxiomEvents([
      {
        scriptName: "notch-api-production",
        outcome: "ok",
        eventTimestamp: TRACE_TIME,
        logs: [
          {
            timestamp: TRACE_TIME,
            level: "info",
            message: [JSON.stringify({ scope: "cron.tokenRefresh", refreshed: 2 })],
          },
        ],
      },
    ]);
    expect(events.find((e) => e.kind === "invocation")).not.toHaveProperty("requestId");
  });
});
