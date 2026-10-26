import { join } from "node:path";
import { pathToFileURL } from "node:url";
import {
  LocalConnectorManifest,
  LocalMetricOutcome,
  LocalMetricResult,
  LocalVerifyResult,
  type ConnectorMetricRequest,
  type PluginHttpCall,
} from "@notch/schemas";
import { allowlistedHttp, PolicyError } from "./execute.ts";

/**
 * Runs a local connector: one app, its credential, and many metrics.
 *
 * The single most important difference from `executeMetric` is that this
 * fetches **several metrics in one process**. A connector with six tiles was
 * otherwise six Node launches per tick, each re-reading the credential and
 * re-paying the ~40 ms start-up — which is the opposite of the background
 * task this is supposed to be. It mirrors `POST /v1/metrics/batch` on the
 * server side, for the same reason.
 *
 * Like `executeMetric` this is the **only** implementation: the MCP server
 * calls it in-process to test a candidate, and the app spawns the CLI which
 * calls the same function. "It passed in `test_connector` and failed in the
 * app" is not a thing that can happen.
 */

export interface ConnectorContext {
  credentials: Readonly<Record<string, string>>;
  timeRange: { from: string; to: string; granularity: string; timeZone: string };
  signal: AbortSignal;
  log(message: string, fields?: Record<string, unknown>): void;
  http: ReturnType<typeof allowlistedHttp>;
}

export interface ConnectorModule {
  verify?: (ctx: ConnectorContext) => Promise<unknown>;
  fetchMetric?: (ctx: ConnectorContext, request: MetricRequest) => Promise<unknown>;
}

/**
 * Re-exported, not redeclared.
 *
 * This was a second copy of the same interface, which is how the contract
 * grew a request `id` in `@notchmetrics/core` while the runner — the one
 * thing that has to echo it — kept a shape that had never heard of it.
 */
export type MetricRequest = ConnectorMetricRequest;

export interface ConnectorRunOptions {
  dir: string;
  manifest: LocalConnectorManifest;
  credentials: Record<string, string>;
  /** Which metrics to fetch, in order. Unknown ids are reported, not thrown. */
  requests: MetricRequest[];
  timeoutMs?: number;
  now?: () => Date;
}

export interface ConnectorRunResult {
  ok: boolean;
  outcomes: LocalMetricOutcome[];
  durationMs: number;
  httpCalls: PluginHttpCall[];
  logs: string[];
}

export interface ConnectorVerifyOutcome {
  ok: boolean;
  result?: LocalVerifyResult;
  code?: "manifest" | "entry" | "timeout" | "policy" | "runtime" | "bad_result";
  message?: string;
  durationMs: number;
  httpCalls: PluginHttpCall[];
  logs: string[];
}

function buildContext(options: {
  manifest: LocalConnectorManifest;
  credentials: Record<string, string>;
  signal: AbortSignal;
  httpCalls: PluginHttpCall[];
  logs: string[];
  timeRange: ConnectorContext["timeRange"];
}): ConnectorContext {
  // Filtered to what the manifest declares and frozen, so a credential the
  // connector never asked for is not quietly readable by its code.
  //
  // `hostCredentials` counts as declared: those are named in the manifest too,
  // just supplied by the app rather than typed by the user. Leaving them out
  // of this set stripped them before the connector ran — the filter is what
  // decides what "declared" means, and it only knew about one of the two
  // places a manifest declares a credential.
  const declared = new Set<string>([
    ...options.manifest.auth.map((field) => field.key),
    ...(options.manifest.hostCredentials ?? []),
  ]);
  const credentials = Object.freeze(
    Object.fromEntries(Object.entries(options.credentials).filter(([key]) => declared.has(key))),
  );

  return {
    credentials,
    timeRange: options.timeRange,
    signal: options.signal,
    log(message, fields) {
      options.logs.push(fields ? `${message} ${JSON.stringify(fields)}` : message);
    },
    http: allowlistedHttp({
      allowedHosts: options.manifest.allowedHosts,
      signal: options.signal,
      httpCalls: options.httpCalls,
    }),
  };
}

async function load(dir: string, entry: string): Promise<ConnectorModule> {
  // Cache-busted, so an agent editing between test runs sees its own edit.
  const url = `${pathToFileURL(join(dir, entry)).href}?t=${Date.now()}`;
  return (await import(url)) as ConnectorModule;
}

function codeFor(
  error: unknown,
  signal: AbortSignal,
): LocalMetricOutcome extends never ? never : "policy" | "timeout" | "runtime" {
  if (signal.aborted) return "timeout";
  if (error instanceof PolicyError) return "policy";
  return "runtime";
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Proves the credential works and names the connection.
 *
 * Called before a connector becomes usable, exactly as a built-in's `verify`
 * is called before an integration row is written. A credential that does not
 * work must not become a connector that silently shows nothing for a week.
 */
export async function verifyConnector(
  options: Omit<ConnectorRunOptions, "requests">,
): Promise<ConnectorVerifyOutcome> {
  const started = Date.now();
  const httpCalls: PluginHttpCall[] = [];
  const logs: string[] = [];
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? options.manifest.timeoutMs,
  );

  const missing = options.manifest.auth
    .filter((field) => field.required && !options.credentials[field.key])
    .map((field) => field.key);
  if (missing.length > 0) {
    clearTimeout(timer);
    return {
      ok: false,
      code: "manifest",
      message: `missing required credential: ${missing.join(", ")}`,
      durationMs: 0,
      httpCalls,
      logs,
    };
  }

  try {
    const module = await load(options.dir, options.manifest.entry);
    if (typeof module.verify !== "function") {
      return {
        ok: false,
        code: "entry",
        message: "The entry file must export a `verify(ctx)` function.",
        durationMs: Date.now() - started,
        httpCalls,
        logs,
      };
    }

    const now = (options.now ?? (() => new Date()))();
    const ctx = buildContext({
      manifest: options.manifest,
      credentials: options.credentials,
      signal: controller.signal,
      httpCalls,
      logs,
      timeRange: {
        from: new Date(now.getTime() - 24 * 3600 * 1000).toISOString(),
        to: now.toISOString(),
        granularity: "day",
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      },
    });

    const raw = await module.verify(ctx);
    const parsed = LocalVerifyResult.safeParse(raw ?? {});
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      return {
        ok: false,
        code: "bad_result",
        message:
          `verify returned something unusable: ${issue?.path.join(".") ?? ""} ${issue?.message ?? ""}`.trim(),
        durationMs: Date.now() - started,
        httpCalls,
        logs,
      };
    }

    // Reported rather than rejected: a connector may legitimately name a
    // metric it no longer declares, and silently dropping the mismatch is how
    // `availableMetrics` used to drift from its own manifest.
    const declared = new Set(options.manifest.metrics.map((metric) => metric.id));
    const unknown = parsed.data.unavailableMetrics.filter((id) => !declared.has(id));
    if (unknown.length > 0) {
      logs.push(`verify named metrics this connector does not declare: ${unknown.join(", ")}`);
    }

    return {
      ok: true,
      result: parsed.data,
      durationMs: Date.now() - started,
      httpCalls,
      logs,
    };
  } catch (error) {
    return {
      ok: false,
      code: codeFor(error, controller.signal),
      message: messageOf(error),
      durationMs: Date.now() - started,
      httpCalls,
      logs,
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Fetches every requested metric, in one process.
 *
 * Failure is **per metric**. One endpoint being down must not blank the other
 * five tiles, which is what a single thrown error would do — and is why the
 * outcome is a list rather than a result.
 */
export async function runConnector(options: ConnectorRunOptions): Promise<ConnectorRunResult> {
  const started = Date.now();
  const httpCalls: PluginHttpCall[] = [];
  const logs: string[] = [];
  const outcomes: LocalMetricOutcome[] = [];
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? options.manifest.timeoutMs,
  );

  try {
    const module = await load(options.dir, options.manifest.entry);
    if (typeof module.fetchMetric !== "function") {
      clearTimeout(timer);
      return {
        ok: false,
        outcomes: options.requests.map((request) => ({
          ok: false as const,
          id: request.id,
          metric: request.metric,
          code: "runtime" as const,
          message: "The entry file must export a `fetchMetric(ctx, request)` function.",
        })),
        durationMs: Date.now() - started,
        httpCalls,
        logs,
      };
    }

    const declared = new Map(options.manifest.metrics.map((metric) => [metric.id, metric]));

    for (const request of options.requests) {
      const descriptor = declared.get(request.metric);
      if (!descriptor) {
        outcomes.push({
          ok: false,
          id: request.id,
          metric: request.metric,
          code: "unsupported",
          message: `${options.manifest.name} does not declare ${request.metric}.`,
        });
        continue;
      }

      // The timeout covers the whole run, not each metric, so a connector
      // cannot buy itself twenty seconds per tile by declaring six of them.
      if (controller.signal.aborted) {
        outcomes.push({
          ok: false,
          id: request.id,
          metric: request.metric,
          code: "timeout",
          message: "The connector ran out of time before this metric.",
        });
        continue;
      }

      const ctx = buildContext({
        manifest: options.manifest,
        credentials: options.credentials,
        signal: controller.signal,
        httpCalls,
        logs,
        timeRange: {
          from: request.from,
          to: request.to,
          granularity: request.granularity,
          timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        },
      });

      try {
        const raw = await module.fetchMetric(ctx, request);
        const parsed = LocalMetricResult.safeParse(raw);
        if (!parsed.success) {
          const issue = parsed.error.issues[0];
          outcomes.push({
            ok: false,
            id: request.id,
            metric: request.metric,
            code: "bad_result",
            message:
              `fetchMetric returned something unusable: ${issue?.path.join(".") ?? ""} ${issue?.message ?? ""}`.trim(),
          });
          continue;
        }
        outcomes.push({ ok: true, id: request.id, metric: request.metric, result: parsed.data });
      } catch (error) {
        outcomes.push({
          ok: false,
          id: request.id,
          metric: request.metric,
          code: codeFor(error, controller.signal),
          message: messageOf(error),
        });
      }
    }

    return {
      ok: outcomes.some((outcome) => outcome.ok),
      outcomes,
      durationMs: Date.now() - started,
      httpCalls,
      logs,
    };
  } catch (error) {
    // The module itself failed to load — every metric fails with the same
    // reason, because none of them had a chance.
    return {
      ok: false,
      outcomes: options.requests.map((request) => ({
        ok: false as const,
        id: request.id,
        metric: request.metric,
        code: codeFor(error, controller.signal),
        message: messageOf(error),
      })),
      durationMs: Date.now() - started,
      httpCalls,
      logs,
    };
  } finally {
    clearTimeout(timer);
  }
}
