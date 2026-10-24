import { describe, expect, it } from "vitest";
import {
  AuthField,
  LocalConnectorManifest,
  LocalMetricResult,
  LocalVerifyResult,
} from "../src/index.ts";

/**
 * The contract an agent writes against.
 *
 * This package is published, so these are the only tests that run against it
 * the way an outside author would see it — nothing here may reach for
 * anything in the monorepo.
 */
const minimal = {
  schemaVersion: 1,
  id: "linear",
  name: "Linear",
  description: "Issues from a Linear workspace.",
  auth: [{ key: "api_key", label: "API key", type: "secret" }],
  allowedHosts: ["api.linear.app"],
  metrics: [
    {
      id: "open_issues",
      label: "Open issues",
      shortLabel: "Issues",
      unit: "count",
      shape: { kind: "scalar" },
      methodology: "Unstarted or started right now.",
    },
  ],
  entry: "connector.mjs",
  createdAt: "2026-10-24T12:00:00.000Z",
  updatedAt: "2026-10-24T12:00:00.000Z",
};

describe("the manifest", () => {
  it("accepts a minimal connector and fills the defaults", () => {
    const manifest = LocalConnectorManifest.parse(minimal);
    expect(manifest.appId).toBe("custom");
    expect(manifest.timeoutMs).toBe(8000);
    expect(manifest.refreshIntervalSeconds).toBe(300);
    // `required` defaults true, so a credential is mandatory unless said
    // otherwise — the safer way round.
    expect(manifest.auth[0]?.required).toBe(true);
  });

  it("refuses a bare wildcard host", () => {
    // A connector that may call anywhere can post the credential it was
    // handed to a pastebin.
    expect(() => LocalConnectorManifest.parse({ ...minimal, allowedHosts: ["*"] })).toThrow();
  });

  it("refuses a connector with no metrics", () => {
    expect(() => LocalConnectorManifest.parse({ ...minimal, metrics: [] })).toThrow();
  });

  it("requires a methodology on every metric", () => {
    // "MRR" is always somebody's definition, and the person reading the tile
    // in six months is rarely the person who wrote it.
    const metrics = [{ ...minimal.metrics[0], methodology: "" }];
    expect(() => LocalConnectorManifest.parse({ ...minimal, metrics })).toThrow();
  });

  it("only lets a windowed shape declare granularities", () => {
    const series = LocalConnectorManifest.parse({
      ...minimal,
      metrics: [
        {
          ...minimal.metrics[0],
          shape: { kind: "series", granularities: ["day", "week"] },
        },
      ],
    });
    expect(series.metrics[0]?.shape).toMatchObject({ kind: "series", compare: true });

    // A scalar has no window, so the field does not exist to get wrong.
    expect(() =>
      LocalConnectorManifest.parse({
        ...minimal,
        metrics: [{ ...minimal.metrics[0], shape: { kind: "scalar", granularities: ["day"] } }],
      }),
    ).not.toThrow();
  });
});

describe("credential keys", () => {
  it("are lower-case, matching the built-in connect forms", () => {
    // The app renders these with the same code it renders a Stripe key with,
    // which is why the convention is not the plugin one.
    expect(() => AuthField.parse({ key: "api_key", label: "K", type: "secret" })).not.toThrow();
    expect(() => AuthField.parse({ key: "API_KEY", label: "K", type: "secret" })).toThrow();
  });
});

describe("what fetchMetric may return", () => {
  it("fills a scalar's absent fields rather than leaving them undefined", () => {
    const result = LocalMetricResult.parse({ value: 12 });
    expect(result.previousValue).toBeNull();
    expect(result.points).toEqual([]);
    expect(result.currency).toBeNull();
  });

  it("refuses a value that is not a number", () => {
    // Caught here rather than rendering as NaN on a tile three days later.
    expect(() => LocalMetricResult.parse({ value: "12" })).toThrow();
  });

  it("accepts list rows with their defaults", () => {
    const result = LocalMetricResult.parse({
      value: 1,
      items: [{ id: "a", t: "2026-10-24T09:00:00.000Z", label: "Row" }],
    });
    expect(result.items?.[0]?.detail).toBeNull();
    expect(result.items?.[0]?.amount).toBeNull();
  });
});

describe("what verify may return", () => {
  it("accepts an empty answer", () => {
    // A connector that proves its key but cannot name the account is fine.
    const result = LocalVerifyResult.parse({});
    expect(result.accountLabel).toBeNull();
    expect(result.unavailableMetrics).toEqual([]);
  });
});
