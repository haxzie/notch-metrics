import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  executeMetric,
  listConnectors,
  promoteStagedConnector,
  readConnector,
  removeConnector,
  runConnector,
  verifyConnector,
  writeConnector,
  lintSource,
  listMetrics,
  metricsRoot,
  promoteStaged,
  readMetric,
  removeMetric,
  writeMetric,
} from "@notch/metric-runtime";
import { LocalConnectorManifest, PluginManifest } from "@notch/schemas";
import type * as z4 from "zod/v4";
import { RUNTIME_DOCS } from "./runtime-docs.ts";
import { manifestInput, type ManifestInput } from "./tool-schemas.ts";
import {
  connectorManifestInput,
  fillConnector,
  type ConnectorManifestInput,
} from "./connector-schemas.ts";
import { CONNECTOR_DOCS } from "./connector-docs.ts";
import { deleteSecrets, hasSecret, readSecret, setSecret } from "./secrets.ts";

const API_URL = process.env.NOTCH_API_URL ?? "https://api.notchmetrics.com";

const server = new McpServer({ name: "notch-metrics", version: "0.1.0" });

function text(value: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: typeof value === "string" ? value : JSON.stringify(value, null, 2),
      },
    ],
  };
}

function problem(message: string) {
  return { ...text(message), isError: true as const };
}

// ── Discovery ───────────────────────────────────────────────────────────────

server.tool(
  "describe_runtime",
  "How to write a Notch Metrics custom metric: the context shape, the return shape, the network policy and the workflow. Call this before writing one.",
  {},
  async () => text(RUNTIME_DOCS),
);

server.tool(
  "list_providers",
  "The built-in integrations (Stripe, Dodo Payments, …) and the metrics each already provides. Check here first — if the number is available from a provider, the user should connect that instead of running custom code.",
  {},
  async () => {
    try {
      const response = await fetch(`${API_URL}/v1/providers`, {
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) return problem(`The provider catalogue returned ${response.status}.`);
      return text(await response.json());
    } catch {
      // Not an error: a custom metric can be written perfectly well offline,
      // and failing the whole call because a catalogue lookup timed out would
      // stop that.
      return text(
        "The provider catalogue is unreachable, so I cannot check whether a built-in integration already covers this. Continuing with a custom metric is fine.",
      );
    }
  },
);

// ── Reading ─────────────────────────────────────────────────────────────────

server.tool(
  "list_metrics",
  "Every custom metric on this Mac, with the secrets each declares and whether a value has been set. Secret values are never returned.",
  {},
  async () => {
    const { ok, broken } = await listMetrics();
    const metrics = await Promise.all(
      ok.map(async (m) => ({
        id: m.id,
        name: m.manifest.name,
        unit: m.manifest.unit,
        allowedHosts: m.manifest.allowedHosts,
        secrets: await Promise.all(
          m.manifest.secrets.map(async (s) => ({
            key: s.key,
            required: s.required,
            configured: await hasSecret(m.id, s.key),
          })),
        ),
      })),
    );
    // Broken metrics are reported rather than skipped. A metric that silently
    // vanishes from the list is one nobody can fix.
    return text({ root: metricsRoot(), metrics, broken });
  },
);

server.tool(
  "get_metric",
  "The manifest and full source of one custom metric, so it can be edited rather than rewritten.",
  { id: z.string() },
  async ({ id }) => {
    try {
      const stored = await readMetric(id);
      return text({ manifest: stored.manifest, source: stored.source, dir: stored.dir });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

// ── Testing ─────────────────────────────────────────────────────────────────

const TestInput = {
  id: z.string().optional().describe("An existing metric. Omit when supplying manifest + source."),
  manifest: manifestInput.optional(),
  source: z.string().optional(),
  secrets: z
    .record(z.string(), z.string())
    .optional()
    .describe("Override values for this run only. Omit to use what is in the Keychain."),
};

server.tool(
  "test_metric",
  "Runs a metric — saved, or supplied inline and never written to disk — and reports the value, timing, every HTTP call it made, and its logs. Iterate here before saving.",
  TestInput,
  async ({ id, manifest, source, secrets }) => {
    try {
      const prepared = await prepare({ id, manifest, source, secrets });
      if ("error" in prepared) return problem(prepared.error);

      const result = await executeMetric(prepared.options);
      if (prepared.cleanup) await prepared.cleanup();

      // The blocked-host hint is the reason httpCalls is in the result at all:
      // it turns "it failed" into "add this host to allowedHosts".
      const blocked = result.httpCalls.filter((c) => c.blocked).map((c) => c.host);
      return text({
        ...result,
        ...(blocked.length > 0
          ? {
              hint: `Blocked by the host policy. Add to allowedHosts: ${[...new Set(blocked)].join(", ")}`,
            }
          : {}),
      });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

/** Either something runnable, or the reason it is not. Explicit, so the
 *  discriminated union narrows at the call site rather than widening. */
type Prepared =
  | { options: Parameters<typeof executeMetric>[0]; cleanup?: () => Promise<void> }
  | { error: string };

async function prepare(input: {
  id?: string;
  manifest?: ManifestInput;
  source?: string;
  secrets?: Record<string, string>;
}): Promise<Prepared> {
  if (input.id) {
    const stored = await readMetric(input.id);
    const secrets = input.secrets ?? (await collectSecrets(stored.manifest));
    return { options: { dir: stored.dir, manifest: stored.manifest, secrets } };
  }

  if (!input.manifest || !input.source) {
    return { error: "Supply either an `id`, or both a `manifest` and a `source`." };
  }

  const findings = lintSource(input.source);
  const errors = findings.filter((f) => f.severity === "error");
  if (errors.length > 0) return { error: errors.map((f) => `• ${f.message}`).join("\n") };

  const manifest = PluginManifest.parse(fill(input.manifest));
  const dir = await writeMetric(manifest, input.source, { staging: true });
  const secrets = input.secrets ?? (await collectSecrets(manifest));
  return {
    options: { dir, manifest, secrets },
    // Staged runs leave nothing behind; a saved metric keeps its directory.
    cleanup: async () => undefined,
  };
}

function fill(manifest: ManifestInput) {
  const now = new Date().toISOString();
  return {
    ...manifest,
    schemaVersion: 1 as const,
    entry: "metric.mjs" as const,
    createdAt: now,
    updatedAt: now,
  };
}

async function collectSecrets(
  manifest: z4.infer<typeof PluginManifest>,
): Promise<Record<string, string>> {
  const entries = await Promise.all(
    manifest.secrets.map(async (s) => [s.key, await readSecret(manifest.id, s.key)] as const),
  );
  return Object.fromEntries(entries.filter((e): e is [string, string] => e[1] !== null));
}

// ── Writing ─────────────────────────────────────────────────────────────────

async function save(
  input: ManifestInput,
  source: string,
  secrets: Record<string, string> | undefined,
  mode: "create" | "update",
) {
  const findings = lintSource(source);
  const errors = findings.filter((f) => f.severity === "error");
  if (errors.length > 0) return problem(errors.map((f) => `• ${f.message}`).join("\n"));

  const manifest = PluginManifest.parse(fill(input));

  const exists = await readMetric(manifest.id).then(
    () => true,
    () => false,
  );
  if (mode === "create" && exists) {
    return problem(`A metric called "${manifest.id}" already exists. Use update_metric.`);
  }
  if (mode === "update" && !exists) {
    return problem(`There is no metric called "${manifest.id}".`);
  }

  // Stage, run, and only then publish. The live directory stays byte-identical
  // until the new version has produced a valid number, so a bad edit cannot
  // blank a widget the user is looking at.
  if (secrets) {
    for (const [key, value] of Object.entries(secrets)) await setSecret(manifest.id, key, value);
  }

  const stagedDir = await writeMetric(manifest, source, { staging: true });
  const result = await executeMetric({
    dir: stagedDir,
    manifest,
    secrets: secrets ?? (await collectSecrets(manifest)),
  });

  if (!result.ok) {
    const blocked = [...new Set(result.httpCalls.filter((c) => c.blocked).map((c) => c.host))];
    return problem(
      [
        `Not saved — the metric failed its test run (${result.code}): ${result.message}`,
        blocked.length > 0 ? `Blocked hosts to add to allowedHosts: ${blocked.join(", ")}` : "",
        result.logs.length > 0 ? `Logs:\n${result.logs.join("\n")}` : "",
      ]
        .filter(Boolean)
        .join("\n\n"),
    );
  }

  const dir = await promoteStaged(manifest.id);
  const warnings = findings.filter((f) => f.severity === "warning").map((f) => f.message);

  return text({
    saved: dir,
    testRun: {
      value: result.result.value,
      durationMs: result.durationMs,
      httpCalls: result.httpCalls,
    },
    warnings,
    nextStep:
      manifest.secrets.length > 0 && !secrets
        ? `Set each declared secret with set_metric_secret, then ask the user to enable "${manifest.name}" in Notch Metrics → Settings → Custom Metrics.`
        : `Ask the user to enable "${manifest.name}" in Notch Metrics → Settings → Custom Metrics. A new metric is not executed until they do.`,
  });
}

server.tool(
  "create_metric",
  "Saves a new custom metric. It is staged, test-run, and only published if it produces a valid number. Refuses a source containing anything key-shaped.",
  {
    manifest: manifestInput,
    source: z.string(),
    secrets: z.record(z.string(), z.string()).optional(),
  },
  ({ manifest, source, secrets }) => save(manifest, source, secrets, "create"),
);

server.tool(
  "update_metric",
  "Replaces an existing metric. Same staging rule: the live version is untouched unless the new one works.",
  {
    manifest: manifestInput,
    source: z.string(),
    secrets: z.record(z.string(), z.string()).optional(),
  },
  ({ manifest, source, secrets }) => save(manifest, source, secrets, "update"),
);

server.tool(
  "set_metric_secret",
  "Stores one declared secret in the macOS Keychain. The value never touches disk and is never echoed back. macOS may ask the user to authorise access the first time.",
  { id: z.string(), key: z.string(), value: z.string() },
  async ({ id, key, value }) => {
    try {
      const stored = await readMetric(id);
      if (!stored.manifest.secrets.some((s) => s.key === key)) {
        return problem(
          `"${key}" is not declared in that metric's manifest. Add it to \`secrets\` with update_metric first — the declaration is what tells the app which values to hand the runner.`,
        );
      }
      await setSecret(id, key, value);
      return text({ ok: true, id, key, configured: true });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

server.tool(
  "delete_metric",
  "Removes a custom metric from this Mac. Its Keychain entries are left alone and reported back.",
  { id: z.string(), confirm: z.literal(true) },
  async ({ id }) => {
    try {
      const stored = await readMetric(id);
      const keys = stored.manifest.secrets.map((s) => s.key);
      await removeMetric(id);
      await deleteSecrets(id, keys);
      return text({
        deleted: id,
        removedSecrets: keys,
        note: "Any widget pointing at this metric will show as unavailable until the user removes it.",
      });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

// ── Connectors ──────────────────────────────────────────────────────────────
//
// A connector is one app, its credential, and every metric it offers. The
// single-metric tools above remain for a one-off number; this is the unit for
// "I have an API key and I want six tiles from it".

server.tool(
  "describe_connector_runtime",
  "Read this before writing a connector. The module contract, the four metric shapes, the credential rules and the host allowlist.",
  {},
  () => text(CONNECTOR_DOCS),
);

server.tool(
  "list_connectors",
  "Every connector registered on this machine, and any whose manifest no longer parses.",
  {},
  async () => {
    const { ok, broken } = await listConnectors();
    return text({
      connectors: await Promise.all(
        ok.map(async ({ manifest }) => ({
          id: manifest.id,
          name: manifest.name,
          metrics: manifest.metrics.map((metric) => metric.id),
          allowedHosts: manifest.allowedHosts,
          credentials: await Promise.all(
            manifest.auth.map(async (field) => ({
              key: field.key,
              required: field.required,
              configured: await hasSecret(manifest.id, field.key),
            })),
          ),
        })),
      ),
      broken,
    });
  },
);

server.tool(
  "get_connector",
  "The manifest and source of one registered connector.",
  { id: z.string() },
  async ({ id }) => {
    try {
      return text(await readConnector(id));
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

/**
 * Stages a candidate, verifies the credential, fetches every metric once, and
 * promotes only if something worked.
 *
 * The same shape as `create_metric`: nothing reaches the live directory until
 * it has produced a real answer, so a broken rewrite cannot blank a working
 * set of tiles.
 */
async function registerConnector(
  input: ConnectorManifestInput,
  source: string,
  credentials: Record<string, string> | undefined,
  mode: "register" | "refresh",
) {
  const findings = lintSource(source, "connector");
  const blocking = findings.filter((finding) => finding.severity === "error");
  // The credential-shape refusal is the highest-value check in the design:
  // pasting the key into the file is the natural thing to do with one.
  if (blocking.some((finding) => !finding.message.includes("fetchMetric"))) {
    return problem(blocking.map((finding) => finding.message).join("\n"));
  }

  let manifest: LocalConnectorManifest;
  try {
    manifest = LocalConnectorManifest.parse(fillConnector(input));
  } catch (error) {
    return problem(error instanceof Error ? error.message : String(error));
  }

  const existing = await listConnectors();
  const known = existing.ok.some(({ manifest: m }) => m.id === manifest.id);
  if (mode === "register" && known) {
    return problem(`${manifest.id} is already registered. Use refresh_connector to replace it.`);
  }
  if (mode === "refresh" && !known) {
    return problem(`${manifest.id} is not registered yet. Use register_connector.`);
  }

  for (const [key, value] of Object.entries(credentials ?? {})) {
    await setSecret(manifest.id, key, value);
  }

  const supplied: Record<string, string> = {};
  for (const field of manifest.auth) {
    const value = await readSecret(manifest.id, field.key);
    if (value !== null) supplied[field.key] = value;
  }

  const dir = await writeConnector(manifest, source, { staging: true });

  const verified = await verifyConnector({ dir, manifest, credentials: supplied });
  if (!verified.ok) {
    return problem(
      `The credential did not verify, so nothing was registered.\n${verified.code}: ${verified.message}\n` +
        (verified.httpCalls.some((call) => call.blocked)
          ? `Blocked hosts: ${verified.httpCalls
              .filter((c) => c.blocked)
              .map((c) => c.host)
              .join(", ")}. Add them to allowedHosts.`
          : ""),
    );
  }

  const now = new Date();
  const run = await runConnector({
    dir,
    manifest,
    credentials: supplied,
    requests: manifest.metrics.map((metric) => ({
      metric: metric.id,
      params: {},
      range: "30d",
      granularity: "day",
      from: new Date(now.getTime() - 30 * 24 * 3600 * 1000).toISOString(),
      to: now.toISOString(),
      comparePrevious: true,
    })),
  });

  if (!run.ok) {
    return problem(
      `No metric produced a number, so nothing was registered.\n` +
        run.outcomes
          .filter((outcome) => !outcome.ok)
          .map((outcome) => `${outcome.metric}: ${outcome.ok ? "" : outcome.message}`)
          .join("\n"),
    );
  }

  const live = await promoteStagedConnector(manifest.id);

  return text({
    registered: live,
    account: verified.result?.accountLabel ?? null,
    metrics: run.outcomes.map((outcome) =>
      outcome.ok
        ? { metric: outcome.metric, value: outcome.result.value }
        : { metric: outcome.metric, failed: outcome.message },
    ),
    warnings: findings.filter((finding) => finding.severity === "warning").map((f) => f.message),
    nextStep: manifest.auth.some((field) => field.required && !supplied[field.key])
      ? "Set the remaining credentials with set_connector_credential, then enable it in Notch Metrics → Settings."
      : "Tell the user to enable it in Notch Metrics → Settings. A new connector does not run until they do.",
  });
}

server.tool(
  "register_connector",
  "Registers a new connector: one app, its credentials and its metrics. Stages, verifies the credential, fetches every metric once, and publishes only if that worked.",
  {
    manifest: connectorManifestInput,
    source: z.string(),
    credentials: z.record(z.string(), z.string()).optional(),
  },
  ({ manifest, source, credentials }) =>
    registerConnector(manifest, source, credentials, "register"),
);

server.tool(
  "refresh_connector",
  "Replaces a registered connector with a rebuilt one. The live copy is untouched unless the new build verifies and returns a number. The user must re-approve it, because approval is pinned to the contents.",
  {
    manifest: connectorManifestInput,
    source: z.string(),
    credentials: z.record(z.string(), z.string()).optional(),
  },
  ({ manifest, source, credentials }) =>
    registerConnector(manifest, source, credentials, "refresh"),
);

server.tool(
  "set_connector_credential",
  "Stores one declared credential in the macOS Keychain. The value never touches disk and is never echoed back.",
  { id: z.string(), key: z.string(), value: z.string() },
  async ({ id, key, value }) => {
    try {
      const { manifest } = await readConnector(id);
      if (!manifest.auth.some((field) => field.key === key)) {
        return problem(
          `${id} does not declare a credential called ${key}. It declares: ${manifest.auth.map((f) => f.key).join(", ") || "none"}.`,
        );
      }
      await setSecret(id, key, value);
      return text({ ok: true, id, key, configured: true });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

server.tool(
  "delete_connector",
  "Removes a connector and its stored credentials.",
  { id: z.string(), confirm: z.literal(true) },
  async ({ id }) => {
    try {
      const { manifest } = await readConnector(id);
      const keys = manifest.auth.map((field) => field.key);
      await deleteSecrets(id, keys);
      await removeConnector(id);
      return text({
        deleted: id,
        removedCredentials: keys,
        note: "Any widget pointing at this connector will show as unavailable until the user removes it.",
      });
    } catch (error) {
      return problem(error instanceof Error ? error.message : String(error));
    }
  },
);

await server.connect(new StdioServerTransport());
