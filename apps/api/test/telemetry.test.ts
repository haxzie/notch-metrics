import { createExecutionContext, env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { deviceToken, integration, user } from "@notch/db";
import worker from "../src/index.ts";
import { id, randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import { RequestTelemetry, requestIdFrom } from "../src/lib/telemetry.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(integration);
  await db().delete(deviceToken);
  await db().delete(user);
});
afterEach(() => vi.restoreAllMocks());

const ctx = createExecutionContext();

function get(path: string, init: RequestInit = {}) {
  return worker.fetch(new Request(`http://localhost:8787${path}`, init), env, ctx);
}

/** Captures the JSON console lines the request emits. */
function captureLines(): { lines: Record<string, unknown>[] } {
  const lines: Record<string, unknown>[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
    const first = args[0];
    if (typeof first !== "string") return;
    try {
      lines.push(JSON.parse(first) as Record<string, unknown>);
    } catch {
      // Not one of ours.
    }
  });
  return { lines };
}

async function makeDevice() {
  const u = await makeUser();
  const token = randomToken(32);
  await db()
    .insert(deviceToken)
    .values({
      id: id("dev"),
      tokenHash: await sha256Base64Url(token),
      userId: u.id,
      label: "Test Mac",
    });
  return { userId: u.id, token };
}

describe("the request id", () => {
  it("prefers a caller's own, so a client can correlate its retry", () => {
    const headers = new Headers({ "x-request-id": "client-abc-123" });
    expect(requestIdFrom(headers, "ray-1")).toBe("client-abc-123");
  });

  /**
   * It arrives from outside and ends up in a log field. A newline cannot
   * even be constructed here — `Headers` rejects one, which is the runtime
   * refusing header injection before we get a say — so this covers what a
   * header *is* allowed to carry.
   */
  it("strips anything that is not an identifier out of a supplied one", () => {
    const headers = new Headers({ "x-request-id": 'a b"c<e>;drop' });
    expect(requestIdFrom(headers, null)).toBe("abcedrop");
  });

  it("bounds a supplied one", () => {
    const headers = new Headers({ "x-request-id": "a".repeat(5_000) });
    expect(requestIdFrom(headers, null).length).toBeLessThanOrEqual(200);
  });

  /**
   * `cf-ray` is what Cloudflare's own dashboards show, so reusing it means
   * our logs and theirs name the same request.
   */
  it("falls back to cf-ray, then to something unique", () => {
    expect(requestIdFrom(new Headers(), "8f1c-LHR")).toBe("8f1c-LHR");
    const generated = requestIdFrom(new Headers({ "x-request-id": "!!!" }), null);
    expect(generated).toMatch(/[0-9a-f-]{36}/);
  });
});

describe("spans", () => {
  it("times a step and keeps it", async () => {
    const t = new RequestTelemetry("r1");
    await t.span("db.read", async () => "value");
    const lines = captureLines().lines;
    t.finish({ method: "GET", route: "/v1/x", status: 200 });
    const spans = scalar(lines[0], "line").spans as { name: string }[];
    expect(spans.map((s) => s.name)).toEqual(["db.read"]);
  });

  /** The failing step is the one worth timing, so it is recorded and rethrown. */
  it("records a throwing step and lets the error through", async () => {
    const t = new RequestTelemetry("r1");
    await expect(
      t.span("provider.stripe", async () => {
        throw new TypeError("boom");
      }),
    ).rejects.toThrow("boom");

    const lines = captureLines().lines;
    t.finish({ method: "GET", route: "/v1/x", status: 500 });
    const spans = scalar(lines[0], "line").spans as { name: string; error?: string }[];
    expect(spans[0]).toMatchObject({ name: "provider.stripe", error: "TypeError" });
  });

  /**
   * A metric batch fans out per integration, so this is unbounded in
   * principle. A line that grows with somebody's widget count is one that
   * eventually gets dropped whole.
   */
  it("bounds the list and says so rather than silently truncating", async () => {
    const t = new RequestTelemetry("r1");
    for (let i = 0; i < 100; i++) t.record({ name: `call.${i}`, ms: 1 });

    const lines = captureLines().lines;
    t.finish({ method: "GET", route: "/v1/x", status: 200 });
    const line = scalar(lines[0], "line");
    expect((line.spans as unknown[]).length).toBe(40);
    expect(line.spansDropped).toBe(60);
  });
});

describe("the request line", () => {
  it("names the route pattern, never the path that carried a token", async () => {
    const { lines } = captureLines();
    // `/v1/link/:token` — the path holds a live single-use credential.
    await get("/v1/link/s1Ft9xQmAbC3dEfGhIjKlMnOpQrStUvWxYz012345");

    const http = scalar(
      lines.find((l) => l.scope === "http"),
      "http line",
    );
    expect(String(http.route)).not.toContain("s1Ft9xQmA");
    expect(String(http.route).startsWith("/v1/link")).toBe(true);
  });

  it("carries the id that went back on the response", async () => {
    const { lines } = captureLines();
    const response = await get("/health");

    const header = response.headers.get("x-request-id");
    expect(header).toBeTruthy();
    const http = scalar(
      lines.find((l) => l.scope === "http"),
      "http line",
    );
    expect(http.requestId).toBe(header);
    expect(http).toMatchObject({ method: "GET", route: "/health", status: 200 });
    expect(typeof http.ms).toBe("number");
  });

  /**
   * An id on a 500 is the whole point — that is the response somebody will
   * be quoting back, and the line describing it has to be findable by it.
   */
  it("still emits a line, with an id, for a request that matched nothing", async () => {
    const { lines } = captureLines();
    const response = await get("/no-such-endpoint");

    expect(response.status).toBe(404);
    expect(response.headers.get("x-request-id")).toBeTruthy();
    const http = scalar(
      lines.find((l) => l.scope === "http"),
      "http line",
    );
    expect(http).toMatchObject({ status: 404, route: "(unmatched)" });
  });

  it("identifies the caller by id, and never by email", async () => {
    const { userId, token } = await makeDevice();
    const { lines } = captureLines();
    await get("/v1/me", { headers: { authorization: `Bearer ${token}` } });

    const http = scalar(
      lines.find((l) => l.scope === "http"),
      "http line",
    );
    expect(http.userId).toBe(userId);
    expect(http.authKind).toBe("device");
    // The address is personal data, and a log store is not where it was
    // collected to live.
    expect(JSON.stringify(http)).not.toContain("@example.com");
  });

  it("says nothing about a user for an unauthenticated request", async () => {
    const { lines } = captureLines();
    await get("/v1/connectors");

    const http = scalar(
      lines.find((l) => l.scope === "http"),
      "http line",
    );
    expect(http.userId).toBeUndefined();
  });
});
