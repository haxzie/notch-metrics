import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import * as S from "../src/index.ts";

const FIXTURE_DIR = join(import.meta.dirname, "..", "..", "..", "contracts", "fixtures");

const BY_NAME: Record<string, z.ZodType> = {
  "metric-series": S.MetricResult,
  "metric-series-empty": S.MetricResult,
  "metric-series-no-currency": S.MetricResult,
  "metric-error": S.MetricResult,
  "metric-batch": S.MetricBatchResponse,
  "provider-manifest-list": S.ProviderManifestList,
  integration: S.Integration,
  "widget-layout": S.WidgetLayout,
  "latest-json": S.LatestJson,
  "plugin-manifest": S.PluginManifest,
};

describe("committed contract fixtures", () => {
  const files = readdirSync(FIXTURE_DIR).filter((f) => f.endsWith(".json"));

  it("has at least one fixture", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    const name = file.replace(/\.json$/, "");
    it(`${name} parses, and re-parses identically`, () => {
      const schema = BY_NAME[name];
      expect(schema, `no schema registered for fixture ${name}`).toBeDefined();

      const raw: unknown = JSON.parse(readFileSync(join(FIXTURE_DIR, file), "utf8"));
      const parsed = schema!.parse(raw);

      // The fixture is emitted post-parse, so parsing must be a no-op. If it is
      // not, a zod default is being applied at read time — which Swift, having
      // no notion of the default, would decode differently.
      expect(parsed).toEqual(raw);
    });
  }
});

describe("wire enums", () => {
  it("rejects an unknown metric error code", () => {
    // The Swift side decodes enums with an `unknown` fallback so an old app
    // survives a new code. The *server* side must stay strict, or a typo in a
    // route handler ships as a valid-looking payload.
    expect(S.MetricErrorCode.safeParse("teapot").success).toBe(false);
  });
});
