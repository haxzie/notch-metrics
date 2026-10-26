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

let nextRequestId = 0;

function request(metric: string): MetricRequest {
  return {
    // A different id each time, as the app gives each widget its own.
    id: `w_${(nextRequestId += 1)}`,
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

  it("answers one outcome per request, in order, even for the same metric twice", async () => {
    // The property the Mac side matches answers by. Two widgets can ask for
    // the same metric with different params — one npm package per tile — and
    // nothing in an outcome distinguishes them except its position, because
    // `metric` is identical for both. Keying answers by metric id instead
    // made the second overwrite the first and showed one package's number on
    // both tiles.
    const requests = [
      { ...request("open_issues"), params: { team: "ENG" } },
      { ...request("completed") },
      { ...request("open_issues"), params: { team: "OPS" } },
    ];
    const result = await runConnector({ dir, manifest, credentials, requests });

    expect(result.outcomes).toHaveLength(3);
    expect(result.outcomes.map((o) => o.metric)).toEqual([
      "open_issues",
      "completed",
      "open_issues",
    ]);
    // The part that matters: each answer names the request it belongs to, so
    // two widgets on the same metric are told apart by something other than
    // where they happen to sit in the array.
    expect(result.outcomes.map((o) => o.id)).toEqual(requests.map((r) => r.id));
  });

  it("still answers one per request when one of them fails", async () => {
    // Position has to hold through a failure too, or every answer after the
    // broken one lands on the wrong tile.
    const result = await runConnector({
      dir,
      manifest,
      credentials,
      requests: [request("open_issues"), request("explodes"), request("recent")],
    });
    expect(result.outcomes.map((o) => o.metric)).toEqual(["open_issues", "explodes", "recent"]);
  });

  it("passes through a host credential the manifest declares", async () => {
    // Host credentials are declared in the manifest too, just supplied by the
    // app rather than typed by the user. The filter only knew about `auth`,
    // so it stripped them before the connector ran and every metric failed
    // with "no sign-in available" while the app had happily handed one over.
    const result = await runConnector({
      dir,
      manifest: { ...manifest, hostCredentials: ["claude_code_oauth"] },
      credentials: { ...credentials, claude_code_oauth: "oat-visible" },
      requests: [request("echo_credentials")],
    });
    const outcome = only(result.outcomes);
    expect(outcome.ok).toBe(true);
    if (!outcome.ok) return;
    // The connector echoes the credential keys it can see.
    expect(outcome.result.items?.map((i) => i.label)).toContain("claude_code_oauth");
  });

  it("does not pass through a host credential the manifest omits", async () => {
    // The other half, and the one that matters: declaring nothing means
    // receiving nothing, however much the caller supplies.
    const result = await runConnector({
      dir,
      manifest: { ...manifest, hostCredentials: [] },
      credentials: { ...credentials, claude_code_oauth: "oat-hidden" },
      requests: [request("echo_credentials")],
    });
    const outcome = only(result.outcomes);
    if (!outcome.ok) return;
    expect(outcome.result.items?.map((i) => i.label)).not.toContain("claude_code_oauth");
    expect(JSON.stringify(result)).not.toContain("oat-hidden");
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

/**
 * The authoring shape a connector is written in now: one default export,
 * each metric carrying its own `fetch`.
 *
 * The older shape stays supported and is covered by every test above, which
 * is the point of keeping both: a connector already on somebody's Mac cannot
 * be migrated by this repository, so dropping it would stop their widgets at
 * the next app update.
 */
describe("a connector built from metric objects", () => {
  const modernDir = join(import.meta.dirname, "connectors/modern");
  const modernManifest = LocalConnectorManifest.parse(
    JSON.parse(readFileSync(join(modernDir, "manifest.json"), "utf8")),
  );

  function run(metrics: string[]) {
    return runConnector({
      dir: modernDir,
      manifest: modernManifest,
      credentials,
      requests: metrics.map(request),
    });
  }

  it("routes each request to that metric's own fetch", async () => {
    const result = await run(["open_issues", "completed"]);
    expect(result.ok).toBe(true);

    const [open, completed] = result.outcomes;
    expect(open).toMatchObject({ ok: true, metric: "open_issues", result: { value: 12 } });
    // `note` echoes the metric the function was called for, which is what
    // proves the dispatch went to the right object and not to a shared
    // switch that happened to return the right number.
    expect(completed).toMatchObject({
      ok: true,
      metric: "completed",
      result: { value: 7, previousValue: 4, note: "completed" },
    });
  });

  it("verifies through the default export", async () => {
    const result = await verifyConnector({
      dir: modernDir,
      manifest: modernManifest,
      credentials,
    });
    expect(result).toMatchObject({ ok: true, result: { accountLabel: "Acme" } });
  });

  it("keeps one failing metric away from the others", async () => {
    const result = await run(["explodes", "open_issues"]);
    const [failed, fine] = result.outcomes;
    expect(failed).toMatchObject({ ok: false, code: "runtime" });
    expect(fine).toMatchObject({ ok: true, result: { value: 12 } });
  });

  it("refuses a metric the module does not carry", async () => {
    const result = await run(["not_a_metric"]);
    expect(only(result.outcomes)).toMatchObject({
      ok: false,
      code: "unsupported",
    });
  });

  it("answers two widgets on one metric separately", async () => {
    // The id is what tells them apart. Two tiles on `completed` with
    // different params are identical in every other field.
    const result = await run(["completed", "completed"]);
    const ids = result.outcomes.map((outcome) => outcome.id);
    expect(new Set(ids).size).toBe(2);
    expect(result.outcomes.every((outcome) => outcome.ok)).toBe(true);
  });
});
