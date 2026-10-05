#!/usr/bin/env node
/**
 * The runner the Swift app spawns, one metric per invocation.
 *
 * Protocol, and every part of it is load-bearing:
 *
 *   stdin   one JSON line, `{"secrets":{…}}`, then the stream closes.
 *           Not argv — argv is visible in `ps` to every process on the machine.
 *           Not the environment — that is inherited by anything the plugin
 *           spawns and dumped verbatim by most crash reporters.
 *
 *   stdout  exactly one JSON line: the PluginRunResult. `console` is pointed at
 *           stderr before the plugin is imported, so a stray `console.log` in
 *           somebody's metric cannot corrupt the channel.
 *
 *   stderr  logs, warnings, everything else.
 *
 *   exit    0 ok · 1 runtime · 2 validation · 3 timeout · 4 policy.
 *           Swift branches on the code and only parses stdout on 0.
 */
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { PLUGIN_EXIT, PluginManifest, PluginRunInput } from "@notch/schemas";
import { executeMetric } from "./execute.ts";
import { listMetrics } from "./store.ts";

const EXIT_FOR_CODE: Record<string, number> = {
  manifest: PLUGIN_EXIT.validation,
  entry: PLUGIN_EXIT.validation,
  bad_result: PLUGIN_EXIT.validation,
  timeout: PLUGIN_EXIT.timeout,
  policy: PLUGIN_EXIT.policy,
  runtime: PLUGIN_EXIT.runtime,
};

function arg(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return "";
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks).toString("utf8");
}

async function main(): Promise<number> {
  const command = process.argv[2];

  if (command === "--version") {
    process.stdout.write(`${JSON.stringify({ runner: 1 })}\n`);
    return PLUGIN_EXIT.ok;
  }

  if (command === "list") {
    const { ok, broken } = await listMetrics();
    process.stdout.write(
      `${JSON.stringify({
        metrics: ok.map((m) => m.manifest),
        broken,
      })}\n`,
    );
    return PLUGIN_EXIT.ok;
  }

  const dir = arg("dir");
  if (!dir) {
    process.stderr.write("usage: notch-metric-runner <run|check|list> --dir <path>\n");
    return PLUGIN_EXIT.validation;
  }

  let manifest;
  try {
    manifest = PluginManifest.parse(JSON.parse(await readFile(join(dir, "manifest.json"), "utf8")));
  } catch (error) {
    process.stdout.write(
      `${JSON.stringify({
        ok: false,
        code: "manifest",
        message: error instanceof Error ? error.message : String(error),
        durationMs: 0,
        httpCalls: [],
        logs: [],
      })}\n`,
    );
    return PLUGIN_EXIT.validation;
  }

  if (command === "check") {
    // Shape only, no network. What the Settings pane's "validate" button runs,
    // and what CI can run over a fixture without reaching the internet.
    const source = await readFile(join(dir, manifest.entry), "utf8");
    const exports = /export\s+(async\s+)?function\s+fetchMetric/.test(source);
    process.stdout.write(`${JSON.stringify({ ok: exports, manifest })}\n`);
    return exports ? PLUGIN_EXIT.ok : PLUGIN_EXIT.validation;
  }

  if (command !== "run") {
    process.stderr.write(`unknown command: ${String(command)}\n`);
    return PLUGIN_EXIT.validation;
  }

  const stdin = await readStdin();
  const input = PluginRunInput.safeParse(stdin ? JSON.parse(stdin) : {});
  if (!input.success) {
    process.stderr.write('stdin must be one JSON object: {"secrets":{…}}\n');
    return PLUGIN_EXIT.validation;
  }

  // From here on the plugin's own output must not reach stdout. Reassigned
  // rather than deleted so a plugin calling console.log still works — it just
  // lands where logs belong.
  const toStderr = (...args: unknown[]) => {
    process.stderr.write(
      `${args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" ")}\n`,
    );
  };
  console.log = toStderr;
  console.info = toStderr;
  console.warn = toStderr;
  console.error = toStderr;
  console.debug = toStderr;

  const result = await executeMetric({
    dir,
    manifest,
    secrets: input.data.secrets,
    ...(arg("from") && arg("to")
      ? {
          timeRange: {
            from: arg("from")!,
            to: arg("to")!,
            granularity: arg("granularity") ?? "day",
            timeZone: arg("tz") ?? Intl.DateTimeFormat().resolvedOptions().timeZone,
          },
        }
      : {}),
    ...(arg("timeout-ms") ? { timeoutMs: Number(arg("timeout-ms")) } : {}),
  });

  process.stdout.write(`${JSON.stringify(result)}\n`);
  return result.ok ? PLUGIN_EXIT.ok : (EXIT_FOR_CODE[result.code] ?? PLUGIN_EXIT.runtime);
}

main()
  .then((code) => process.exit(code))
  .catch((error: unknown) => {
    process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
    process.exit(PLUGIN_EXIT.runtime);
  });
