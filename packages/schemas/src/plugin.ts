import { z } from "zod";
import { Granularity } from "./money.ts";
import { AppId, PluginId } from "./ids.ts";
import { MetricFormat, MetricPoint, MetricUnit } from "./metric.ts";

/**
 * A custom metric authored by an agent through the MCP server and stored on the
 * user's own machine at
 * `~/Library/Application Support/NotchMetrics/metrics/<id>/manifest.json`.
 */
export const PluginSecretDeclaration = z.object({
  key: z.string().regex(/^[A-Z][A-Z0-9_]*$/),
  label: z.string(),
  help: z.string().optional(),
  required: z.boolean().default(true),
});
export type PluginSecretDeclaration = z.infer<typeof PluginSecretDeclaration>;

export const PluginManifest = z.object({
  schemaVersion: z.literal(1),
  id: PluginId,
  name: z.string().min(1).max(60),
  shortLabel: z.string().max(12),
  description: z.string().max(400),

  /**
   * Which app this number comes from — "github", "plausible", "linear".
   *
   * Every metric in the notch belongs to an app, and a custom one is no
   * exception: a row that reads "GitHub · Stars" is worth more than one that
   * reads "Custom · Stars", and the list view groups by this.
   *
   * Defaults to "custom" rather than being required, so the simplest possible
   * metric is still three fields and a function.
   */
  appId: AppId.default("custom"),
  /** Shown when `appId` is not one the app already knows. */
  appName: z.string().max(40).optional(),

  unit: MetricUnit,
  currency: z.string().length(3).optional(),
  format: MetricFormat.default({ decimals: 0, compact: true, prefix: "", suffix: "" }),
  granularities: z.array(Granularity).nonempty().default(["day"]),
  supportsSeries: z.boolean().default(true),
  /** The app floors this at 60s regardless of what the manifest asks for. */
  refreshIntervalSeconds: z.number().int().min(60).max(86_400).default(300),

  /**
   * Which secrets this metric needs. Names only — never values.
   *
   * The app holds the values in the macOS Keychain and hands them to the runner
   * on stdin. A secret written here would be a secret sitting in a plain-text
   * file inside a directory any agent can read, and this field exists precisely
   * to make that unnecessary.
   */
  secrets: z.array(PluginSecretDeclaration).default([]),

  /**
   * Every host this plugin may reach. Exact names, or a single leading `*.`.
   *
   * No bare `*`. A metric that may call anywhere is a metric that can post every
   * other secret the runner was handed to a pastebin, and "it needs the whole
   * internet" is never true of a number.
   */
  allowedHosts: z
    .array(
      z.string().regex(/^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/),
    )
    .nonempty(),

  timeoutMs: z.number().int().min(1_000).max(20_000).default(8_000),
  entry: z.literal("metric.mjs"),
  author: z.string().optional(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PluginManifest = z.infer<typeof PluginManifest>;

/** What `fetchMetric(ctx)` must return. Validated after the call, not trusted. */
export const PluginResult = z.object({
  value: z.number(),
  unit: MetricUnit.optional(),
  currency: z.string().length(3).optional(),
  series: z.array(MetricPoint).optional(),
  previousValue: z.number().optional(),
  format: MetricFormat.partial().optional(),
  asOf: z.string().optional(),
});
export type PluginResult = z.infer<typeof PluginResult>;

/** What the Swift app writes to the runner's stdin. Secrets live only here. */
export const PluginRunInput = z.object({
  secrets: z.record(z.string(), z.string()).default({}),
});
export type PluginRunInput = z.infer<typeof PluginRunInput>;

export const PluginHttpCall = z.object({
  host: z.string(),
  method: z.string(),
  status: z.number().int().nullable(),
  ms: z.number(),
  blocked: z.boolean().default(false),
});
export type PluginHttpCall = z.infer<typeof PluginHttpCall>;

/**
 * The runner's single line of stdout.
 *
 * `httpCalls` is not diagnostics for its own sake: it is how an agent running
 * `test_metric` discovers that it needs to add a host to `allowedHosts`,
 * instead of guessing from a generic failure.
 */
export const PluginRunResult = z.discriminatedUnion("ok", [
  z.object({
    ok: z.literal(true),
    result: PluginResult,
    durationMs: z.number(),
    httpCalls: z.array(PluginHttpCall),
    logs: z.array(z.string()),
  }),
  z.object({
    ok: z.literal(false),
    code: z.enum(["manifest", "entry", "timeout", "policy", "runtime", "bad_result"]),
    message: z.string(),
    durationMs: z.number(),
    httpCalls: z.array(PluginHttpCall),
    logs: z.array(z.string()),
  }),
]);
export type PluginRunResult = z.infer<typeof PluginRunResult>;

/** Exit codes, so the Swift side can branch before parsing anything. */
export const PLUGIN_EXIT = {
  ok: 0,
  runtime: 1,
  validation: 2,
  timeout: 3,
  policy: 4,
} as const;
