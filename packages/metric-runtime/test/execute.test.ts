import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { PluginManifest } from "@notch/schemas";
import { executeMetric } from "../src/execute.ts";

const PLUGINS = join(import.meta.dirname, "plugins");

async function run(name: string, secrets: Record<string, string> = {}) {
  const dir = join(PLUGINS, name);
  const manifest = PluginManifest.parse(
    JSON.parse(await readFile(join(dir, "manifest.json"), "utf8")),
  );
  return executeMetric({ dir, manifest, secrets });
}

describe("executeMetric", () => {
  it("runs a well-formed metric", async () => {
    const result = await run("ok");
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.result.value).toBe(42);
      expect(result.logs).toContain("working");
    }
  });

  it("times out a metric that ignores the abort signal", async () => {
    const result = await run("slow");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("timeout");
  }, 15_000);

  it("blocks a call to a host outside allowedHosts and records the attempt", async () => {
    // The threat this whole policy exists for: a plugin handed a secret trying
    // to post it somewhere it was never allowed to reach.
    const result = await run("exfiltrates", { GITHUB_TOKEN: "ghp_secret_value_here" });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("policy");
      expect(result.message).toMatch(/not in allowedHosts/);
    }
    // Recorded as blocked, which is how `test_metric` tells an agent what to
    // add to allowedHosts rather than leaving it to guess.
    expect(result.httpCalls).toContainEqual(
      expect.objectContaining({ host: "evil.example.com", blocked: true }),
    );
    // And the secret itself is nowhere in what we hand back.
    expect(JSON.stringify(result)).not.toContain("ghp_secret_value_here");
  });

  it("rejects a result that is the wrong shape, naming the field", async () => {
    const result = await run("bad-return");
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("bad_result");
      expect(result.message).toMatch(/value/);
    }
  });

  it("rejects a module with no fetchMetric export", async () => {
    const result = await run("no-export");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("entry");
  });

  it("names a missing required secret before importing the module", async () => {
    const result = await run("needs-secret");
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("manifest");
      expect(result.message).toContain("GITHUB_TOKEN");
    }
  });

  it("passes only the secrets the manifest declared", async () => {
    const result = await run("needs-secret", {
      GITHUB_TOKEN: "declared",
      SOMETHING_ELSE: "not declared",
    });
    expect(result.ok).toBe(true);
  });
});
