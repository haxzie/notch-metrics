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
import { lintSource } from "./lint.ts";
import {
  LocalConnectorManifest,
  PLUGIN_EXIT,
  PluginManifest,
  PluginRunInput,
} from "@notch/schemas";
import { executeMetric } from "./execute.ts";
import { runConnector, verifyConnector, type MetricRequest } from "./connector.ts";
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
    process.stderr.write(
      "usage: notch-metric-runner <run|check|list|connect|fetch> --dir <path>\n",
    );
    return PLUGIN_EXIT.validation;
  }

  // Connectors are a different manifest and a different entry, so they branch
  // before the plugin manifest is parsed — a connector's manifest.json is not
  // a `PluginManifest` and reporting it as a broken one would be a confusing
  // way to say "wrong command".
  if (command === "connect" || command === "fetch") {
    return await connectorCommand(command, dir);
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
    // The same check `lintSource` makes, through the same function — these
    // were two copies of one regex, and only one of them learned that a
    // bundler writes `export { fetchMetric }` rather than
    // `export async function fetchMetric`.
    const exports = lintSource(source).every(
      (finding) => finding.severity !== "error" || !finding.message.includes("fetchMetric"),
    );
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

/**
 * `connect` proves the credential; `fetch` returns several metrics at once.
 *
 * Both read one JSON object on stdin — `{"credentials":{…},"requests":[…]}` —
 * for the same reason the plugin path does: argv is world-readable through
 * `ps`, and the environment is inherited by anything the connector spawns.
 *
 * One process answers every requested metric. A connector with six tiles was
 * otherwise six launches a tick.
 */
async function connectorCommand(command: "connect" | "fetch", dir: string): Promise<number> {
  let manifest;
  try {
    manifest = LocalConnectorManifest.parse(
      JSON.parse(await readFile(join(dir, "manifest.json"), "utf8")),
    );
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

  const stdin = await readStdin();
  let input: { credentials?: Record<string, string>; requests?: MetricRequest[] };
  try {
    input = stdin ? (JSON.parse(stdin) as typeof input) : {};
  } catch {
    process.stderr.write('stdin must be one JSON object: {"credentials":{…},"requests":[…]}\n');
    return PLUGIN_EXIT.validation;
  }

  // The connector's own output must not reach stdout, which carries the one
  // result line. Reassigned rather than deleted, so `console.log` still works.
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

  const credentials = input.credentials ?? {};

  if (command === "connect") {
    const outcome = await verifyConnector({ dir, manifest, credentials });
    process.stdout.write(`${JSON.stringify(outcome)}\n`);
    return outcome.ok
      ? PLUGIN_EXIT.ok
      : (EXIT_FOR_CODE[outcome.code ?? "runtime"] ?? PLUGIN_EXIT.runtime);
  }

  const result = await runConnector({
    dir,
    manifest,
    credentials,
    requests: input.requests ?? [],
  });
  process.stdout.write(`${JSON.stringify(result)}\n`);
  // Exit 0 whenever *anything* succeeded. A connector where one metric's
  // endpoint is down is not a failed run, and treating it as one would blank
  // five working tiles.
  return result.ok ? PLUGIN_EXIT.ok : PLUGIN_EXIT.runtime;
}
