import { createExecutionContext, env } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index.ts";

const ctx = createExecutionContext();
const KEY = "desktop/latest.json";

const manifest = (overrides: Record<string, unknown> = {}) => ({
  version: "0.3.0",
  build: 140,
  tag: "mac-v0.3.0",
  publishedAt: "2026-10-15T00:00:00Z",
  platform: "darwin-arm64",
  minimumSystemVersion: "14.0",
  filename: "NotchMetrics-0.3.0-arm64.dmg",
  url: "https://assets.notchmetrics.com/desktop/0.3.0/NotchMetrics-0.3.0-arm64.dmg",
  size: 18_000_000,
  sha256: "a".repeat(64),
  notes: "https://github.com/haxzie/notch-metrics/releases/tag/mac-v0.3.0",
  mandatory: false,
  ...overrides,
});

async function publish(body: unknown) {
  await env.ASSETS_BUCKET.put(KEY, JSON.stringify(body));
}

function get(path: string, bindings: Record<string, unknown> = {}) {
  return worker.fetch(
    new Request(`https://api.test${path}`),
    { ...env, ...bindings } as typeof env,
    ctx,
  );
}

afterEach(async () => {
  await env.ASSETS_BUCKET.delete(KEY);
});

describe("the update feed", () => {
  it("serves the manifest once a release is mirrored", async () => {
    await publish(manifest());
    const response = await get("/v1/updates/latest");

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ version: "0.3.0", build: 140 });
  });

  it("says there is no release rather than erroring, before the first one", async () => {
    const response = await get("/v1/updates/latest");
    expect(response.status).toBe(404);
  });

  // The whole point of the app polling the Worker instead of the bucket.
  it("withholds anything that is not the pinned version", async () => {
    await publish(manifest());
    expect((await get("/v1/updates/latest", { PINNED_VERSION: "0.2.0" })).status).toBe(404);
    expect((await get("/v1/updates/latest", { PINNED_VERSION: "0.3.0" })).status).toBe(200);
  });

  // An updater acting on a half-readable manifest is worse than one that does
  // nothing, so this must not degrade into a 200 with missing fields.
  it("refuses a manifest that does not parse", async () => {
    await publish({ version: "0.3.0" });
    expect((await get("/v1/updates/latest")).status).toBe(502);
  });

  // Build 0 is what a mirror writes from an unset variable. It parses
  // perfectly and is lower than every installed copy, so it does not break a
  // release — it makes the release invisible to everyone, silently.
  it("refuses a manifest whose build number is zero", async () => {
    await publish(manifest({ build: 0 }));
    expect((await get("/v1/updates/latest")).status).toBe(502);
    expect((await get("/v1/updates/download")).status).toBe(502);
  });
});

describe("the download redirect", () => {
  it("sends a browser to the object on R2", async () => {
    await publish(manifest());
    const response = await get("/v1/updates/download");

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe(manifest().url);
    // A cached redirect would outlive the release it points at.
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  // Without this the website's button is the one route around a rollback.
  it("is withheld by PINNED_VERSION too", async () => {
    await publish(manifest());
    const response = await get("/v1/updates/download", { PINNED_VERSION: "0.2.0" });
    expect(response.status).toBe(404);
  });

  it("404s rather than redirecting nowhere when there is no release", async () => {
    expect((await get("/v1/updates/download")).status).toBe(404);
  });
});
