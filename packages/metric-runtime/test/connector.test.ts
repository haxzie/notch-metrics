import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { LocalConnectorManifest } from "@notch/schemas";
import { runConnector, verifyConnector, type MetricRequest } from "../src/connector.ts";

/**
 * A local connector: one app, one credential, several metrics.
 *
 * The thing a `PluginManifest` could not express. Ten numbers from one API
 * used to mean ten directories, ten copies of the token and ten approvals.
 */
const dir = join(import.meta.dirname, "connectors/linear");
const manifest = LocalConnectorManifest.parse(
  JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8")),
);

const credentials = { api_key: "lin_api_notarealkey", team: "ENG" };

/**
 * `noUncheckedIndexedAccess` makes every index `T | undefined`, which is
 * correct and tedious where the row is known to be there.
 */
function only<T>(values: T[]): T {
  const [first] = values;
  if (first === undefined) throw new Error("expected exactly one outcome");
  return first;
}

function request(metric: string): MetricRequest {
  return {
    metric,
    params: {},
    range: "7d",
    granularity: "day",
    from: "2026-10-17T00:00:00.000Z",
    to: "2026-10-24T00:00:00.000Z",
    comparePrevious: true,
  };
}

describe("verifying a connector", () => {
  it("names the connection", async () => {
    const outcome = await verifyConnector({ dir, manifest, credentials });
    expect(outcome.ok).toBe(true);
    expect(outcome.result?.accountLabel).toBe("Acme");
  });

  it("refuses before loading anything when a required credential is missing", async () => {
    // Before the import, deliberately: a connector should not get to run code
    // at all on a credential set it already cannot work with.
    const outcome = await verifyConnector({ dir, manifest, credentials: {} });
    expect(outcome.ok).toBe(false);
    expect(outcome.code).toBe("manifest");
    expect(outcome.message).toContain("api_key");
    expect(outcome.httpCalls).toHaveLength(0);
  });

  it("does not mind an optional credential being absent", async () => {
    const outcome = await verifyConnector({
      dir,
      manifest,
      credentials: { api_key: "k" },
    });
    expect(outcome.ok).toBe(true);
  });
});

describe("running a connector", () => {
  it("answers several metrics from one process", async () => {
    // The whole point of the format. Six tiles used to be six Node launches
    // per tick, each re-reading the credential and re-paying start-up.
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("open_issues"), request("completed"), request("recent")],
    });

    expect(result.ok).toBe(true);
    expect(result.outcomes.map((o) => o.metric)).toEqual(["open_issues", "completed", "recent"]);
    expect(result.outcomes.every((o) => o.ok)).toBe(true);
  });

  it("fills in the defaults a shape implies", async () => {
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("open_issues")],
    });
    const outcome = result.outcomes[0];
    expect(outcome?.ok).toBe(true);
    if (!outcome?.ok) return;
    // A scalar returning only `value` still arrives complete, so the Swift
    // side never has to decide what a missing field meant.
    expect(outcome.result.value).toBe(12);
    expect(outcome.result.previousValue).toBeNull();
    expect(outcome.result.points).toEqual([]);
  });

  it("carries a series and its comparison through", async () => {
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("completed")],
    });
    const outcome = result.outcomes[0];
    if (!outcome?.ok) throw new Error("expected success");
    expect(outcome.result.value).toBe(7);
    expect(outcome.result.previousValue).toBe(4);
    expect(outcome.result.points).toHaveLength(2);
  });

  it("carries list rows through", async () => {
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("recent")],
    });
    const outcome = result.outcomes[0];
    if (!outcome?.ok) throw new Error("expected success");
    expect(outcome.result.items).toHaveLength(2);
    expect(outcome.result.items?.[0]?.label).toBe("Fix the notch");
    // Defaulted rather than required, so a row is three fields and a state.
    expect(outcome.result.items?.[0]?.detail).toBeNull();
  });

  it("one broken metric does not blank the others", async () => {
    // The reason the outcome is a list rather than a result. A single thrown
    // error would take every tile in the connector down with it.
    const result = await runConnector({
      dir,
      manifest: { ...manifest, metrics: [...manifest.metrics] },
      credentials,
      requests: [request("open_issues"), request("explodes"), request("recent")],
    });

    expect(result.ok).toBe(true);
    expect(result.outcomes[0]?.ok).toBe(true);
    expect(result.outcomes[1]?.ok).toBe(false);
    expect(result.outcomes[2]?.ok).toBe(true);
  });

  it("refuses a metric the manifest does not declare", async () => {
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("invented")],
    });
    const outcome = only(result.outcomes);
    expect(outcome.ok).toBe(false);
    if (outcome.ok) return;
    expect(outcome.code).toBe("unsupported");
  });

  it("hands the connector only the credentials it declared", async () => {
    // `sneaky` is not in `auth`, so the connector's own code cannot read it
    // even though the caller passed it in.
    const result = await runConnector({
      dir,
      manifest,
      credentials: { ...credentials, sneaky: "should-not-be-visible" },
      requests: [request("open_issues")],
    });
    expect(result.ok).toBe(true);
    expect(JSON.stringify(result)).not.toContain("should-not-be-visible");
  });
});
