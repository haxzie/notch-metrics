import { spawn } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { PLUGIN_EXIT, PluginRunResult } from "@notch/schemas";

const CLI = join(import.meta.dirname, "..", "src", "cli.ts");
const PLUGINS = join(import.meta.dirname, "plugins");

/**
 * Spawned rather than `execFile`, because the protocol is the point: the
 * secrets go in on stdin and the stream is then closed. `execFile` has no way
 * to write stdin, and a runner whose stdin never closes waits forever — which
 * is exactly what the Swift side must not do either.
 */
function invoke(plugin: string, secrets: Record<string, string> = {}) {
  return new Promise<{ code: number; stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(
      process.execPath,
      ["--experimental-strip-types", "--no-warnings", CLI, "run", "--dir", join(PLUGINS, plugin)],
      { stdio: ["pipe", "pipe", "pipe"] },
    );

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c: Buffer) => (stdout += c.toString()));
    child.stderr.on("data", (c: Buffer) => (stderr += c.toString()));
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? -1, stdout, stderr }));

    child.stdin.write(JSON.stringify({ secrets }));
    child.stdin.end();
  });
}

describe("the runner protocol", () => {
  it("writes exactly one JSON line to stdout and exits 0", async () => {
    const { code, stdout } = await invoke("ok");
    expect(code).toBe(PLUGIN_EXIT.ok);
    expect(stdout.trimEnd().split("\n")).toHaveLength(1);
    expect(() => PluginRunResult.parse(JSON.parse(stdout))).not.toThrow();
  }, 20_000);

  it("keeps a chatty plugin's console.log off stdout", async () => {
    // The protocol's one fragile point. A plugin that logs a JSON object would
    // otherwise produce two parseable lines, and the Swift side reads the first.
    const { code, stdout, stderr } = await invoke("chatty");
    expect(code).toBe(PLUGIN_EXIT.ok);
    expect(stdout.trimEnd().split("\n")).toHaveLength(1);

    const parsed = PluginRunResult.parse(JSON.parse(stdout));
    expect(parsed.ok && parsed.result.value).toBe(7);
    expect(stderr).toContain("this must not reach stdout");
  }, 20_000);

  it("exits 4 on a policy violation", async () => {
    const { code } = await invoke("exfiltrates", { GITHUB_TOKEN: "x" });
    expect(code).toBe(PLUGIN_EXIT.policy);
  }, 20_000);

  it("exits 2 on a bad result", async () => {
    expect((await invoke("bad-return")).code).toBe(PLUGIN_EXIT.validation);
  }, 20_000);

  it("exits 3 on a timeout", async () => {
    expect((await invoke("slow")).code).toBe(PLUGIN_EXIT.timeout);
  }, 20_000);
});
