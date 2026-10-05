import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

/**
 * Plugin secrets, in the macOS Keychain.
 *
 * The MCP server and the Mac app never talk to each other. They agree on one
 * thing only — this service/account naming — and both reach the Keychain
 * through `/usr/bin/security`. Documented here because it is the single shared
 * contract between a published npm package and a signed .app.
 *
 * An `npx`-installed server is not signed with the app's team id, so it cannot
 * share a Keychain access group. The consequence is a one-time authorisation
 * prompt per plugin, which is accepted for v1; a local socket on the app is the
 * cleaner answer and is deferred.
 */
export function service(pluginId: string): string {
  return `app.notchmetrics.plugin.${pluginId}`;
}

export async function setSecret(pluginId: string, key: string, value: string): Promise<void> {
  // The value goes in argv here, which is the one place this design has to
  // compromise: `security` offers no stdin form for add-generic-password. The
  // exposure is a single local invocation rather than a file on disk, and the
  // alternative — writing it anywhere — is worse.
  await run("/usr/bin/security", [
    "add-generic-password",
    "-U", // update in place rather than erroring on a second set
    "-s",
    service(pluginId),
    "-a",
    key,
    "-w",
    value,
  ]);
}

/** Existence only. The value is never read back into this process. */
export async function hasSecret(pluginId: string, key: string): Promise<boolean> {
  try {
    await run("/usr/bin/security", ["find-generic-password", "-s", service(pluginId), "-a", key]);
    return true;
  } catch {
    return false;
  }
}

export async function readSecret(pluginId: string, key: string): Promise<string | null> {
  try {
    const { stdout } = await run("/usr/bin/security", [
      "find-generic-password",
      "-s",
      service(pluginId),
      "-a",
      key,
      "-w",
    ]);
    return stdout.trim();
  } catch {
    return null;
  }
}

export async function deleteSecrets(pluginId: string, keys: string[]): Promise<void> {
  for (const key of keys) {
    await run("/usr/bin/security", [
      "delete-generic-password",
      "-s",
      service(pluginId),
      "-a",
      key,
    ]).catch(() => undefined);
  }
}
