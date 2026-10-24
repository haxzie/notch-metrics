import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { account } from "../src/secrets.ts";

/**
 * The Keychain item this server writes must be the one the app reads.
 *
 * These two processes never talk. They agree on a service and an account
 * format and nothing else, and for a while they did not agree at all: the
 * server wrote service `app.notchmetrics.plugin.<id>` with account `<KEY>`
 * while `PluginRunner` looked up service `com.notchmetrics.app` with account
 * `plugin.<id>.<KEY>`. Both halves worked in isolation. `set_metric_secret`
 * reported success, and every run then failed with a missing required secret.
 *
 * So this reads the Swift rather than restating it. A rename on either side
 * fails here, which is the only place the pair is checked at all.
 */
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const swift = (path: string) => readFileSync(join(ROOT, path), "utf8");

describe("the Keychain naming the app expects", () => {
  it("uses the service KeychainSecretStore defaults to", () => {
    // `public init(service: String = AppPaths.bundleIdentifier)`
    const store = swift("apps/mac/Kit/Sources/MetricsCore/Keychain.swift");
    expect(store).toContain("service: String = AppPaths.bundleIdentifier");

    const paths = swift("apps/mac/Kit/Sources/MetricsCore/Paths.swift");
    const bundleId = /bundleIdentifier = "([^"]+)"/.exec(paths)?.[1];
    expect(bundleId).toBe("com.notchmetrics.app");

    const source = readFileSync(join(ROOT, "apps/mcp/src/secrets.ts"), "utf8");
    expect(source).toContain(`const SERVICE = "${bundleId}"`);
  });

  it("builds the account the way SecretKey.plugin does", () => {
    // `SecretKey(account: "plugin.\(id).\(name)")`
    const store = swift("apps/mac/Kit/Sources/MetricsCore/Keychain.swift");
    expect(store).toContain('SecretKey(account: "plugin.\\(id).\\(name)")');

    expect(account("stars", "GITHUB_TOKEN")).toBe("plugin.stars.GITHUB_TOKEN");
  });

  it("stays under the prefix a plugin delete wipes by", () => {
    // `pluginPrefix(_:)` is how removing a plugin removes its secrets, so an
    // account that did not start with it would leak one item per secret.
    const store = swift("apps/mac/Kit/Sources/MetricsCore/Keychain.swift");
    expect(store).toContain('pluginPrefix(_ id: String) -> String { "plugin.\\(id)." }');

    expect(account("stars", "GITHUB_TOKEN").startsWith("plugin.stars.")).toBe(true);
  });
});
