import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import {
  PluginResult,
  type PluginHttpCall,
  type PluginManifest,
  type PluginRunResult,
} from "@notch/schemas";
import { MAX_REDIRECTS, MAX_RESPONSE_BYTES, checkHost } from "./policy.ts";
import { readMetric } from "./store.ts";

export class PolicyError extends Error {}

export interface ExecuteOptions {
  dir: string;
  manifest: PluginManifest;
  source?: string;
  secrets: Record<string, string>;
  timeRange?: { from: string; to: string; granularity: string; timeZone: string };
  timeoutMs?: number;
}

/**
 * Runs one custom metric and returns the single result line.
 *
 * This is the *only* implementation. The MCP server's `test_metric` calls it
 * in-process and the Swift app spawns `cli.ts`, which calls it too — if there
 * were two executors, `test_metric` would be validating against semantics the
 * shipped runner does not have, and "it passed the test but fails in the app"
 * would be a routine bug report.
 */
export async function executeMetric(options: ExecuteOptions): Promise<PluginRunResult> {
  const started = Date.now();
  const httpCalls: PluginHttpCall[] = [];
  const logs: string[] = [];
  const { manifest } = options;

  const fail = (
    code: Extract<PluginRunResult, { ok: false }>["code"],
    message: string,
  ): PluginRunResult => ({
    ok: false,
    code,
    message,
    durationMs: Date.now() - started,
    httpCalls,
    logs,
  });

  const missing = manifest.secrets
    .filter((s) => s.required && !options.secrets[s.key])
    .map((s) => s.key);
  if (missing.length > 0) {
    // Checked before the module is imported, so the failure names the secret
    // instead of surfacing as `undefined` inside somebody's Authorization
    // header and coming back as a 401 from the provider.
    return fail(
      "manifest",
      `missing required secret${missing.length > 1 ? "s" : ""}: ${missing.join(", ")}`,
    );
  }

  const controller = new AbortController();
  const timeoutMs = options.timeoutMs ?? manifest.timeoutMs;
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const ctx = buildContext({ ...options, signal: controller.signal, httpCalls, logs });

    const entry = join(options.dir, manifest.entry);
    const module: unknown = await import(`${pathToFileURL(entry).href}?t=${Date.now()}`);
    const fn = (module as { fetchMetric?: unknown }).fetchMetric;
    if (typeof fn !== "function") {
      return fail("entry", `${manifest.entry} must export an async function named fetchMetric`);
    }

    const raw: unknown = await (fn as (c: unknown) => Promise<unknown>)(ctx);
    if (controller.signal.aborted) return fail("timeout", `timed out after ${timeoutMs}ms`);

    // Validated *after* the call, never trusted. A plugin returning
    // `{ value: "123" }` must fail here with a message naming the field, not
    // render as NaN in somebody's notch three days later.
    const parsed = PluginResult.safeParse(raw);
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      return fail(
        "bad_result",
        `fetchMetric returned something unusable: ${issue?.path.join(".") || "(root)"} ${issue?.message ?? ""}`.trim(),
      );
    }

    return { ok: true, result: parsed.data, durationMs: Date.now() - started, httpCalls, logs };
  } catch (error) {
    if (controller.signal.aborted) return fail("timeout", `timed out after ${timeoutMs}ms`);
    if (error instanceof PolicyError) return fail("policy", error.message);
    return fail("runtime", error instanceof Error ? error.message : String(error));
  } finally {
    clearTimeout(timer);
  }
}

function buildContext(
  options: ExecuteOptions & {
    signal: AbortSignal;
    httpCalls: PluginHttpCall[];
    logs: string[];
  },
) {
  const { manifest, dir, signal, httpCalls, logs } = options;
  const cachePath = join(dir, ".cache.json");

  const allowedSecrets = new Set(manifest.secrets.map((s) => s.key));
  const secrets = Object.freeze(
    Object.fromEntries(Object.entries(options.secrets).filter(([key]) => allowedSecrets.has(key))),
  );

  return {
    secrets,

    timeRange: options.timeRange ?? {
      from: new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString(),
      to: new Date().toISOString(),
      granularity: manifest.granularities[0],
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    },

    signal,

    log(message: string, fields?: Record<string, unknown>) {
      logs.push(fields ? `${message} ${JSON.stringify(fields)}` : message);
    },

    http: allowlistedHttp({ allowedHosts: manifest.allowedHosts, signal, httpCalls }),

    cache: {
      async get<T>(key: string): Promise<T | null> {
        try {
          const store = JSON.parse(await readFile(cachePath, "utf8")) as Record<
            string,
            { value: T; expiresAt: number }
          >;
          const entry = store[key];
          if (!entry || entry.expiresAt < Date.now()) return null;
          return entry.value;
        } catch {
          return null;
        }
      },
      async set(key: string, value: unknown, ttlSeconds: number): Promise<void> {
        let store: Record<string, unknown> = {};
        try {
          store = JSON.parse(await readFile(cachePath, "utf8")) as Record<string, unknown>;
        } catch {
          /* first write */
        }
        store[key] = { value, expiresAt: Date.now() + ttlSeconds * 1000 };
        const serialised = JSON.stringify(store);
        // Bounded: the cache is a convenience for paging a slow API, not a
        // database, and an unbounded JSON file in Application Support is a
        // disk-space bug waiting to be filed.
        if (serialised.length > 64 * 1024)
          throw new PolicyError("the metric cache is limited to 64 KB");
        await writeFile(cachePath, serialised, "utf8");
      },
    },
  };
}

function safeHost(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return "(invalid)";
  }
}

/** Convenience for `test_metric` against something already on disk. */
export async function executeStored(
  id: string,
  secrets: Record<string, string>,
  timeoutMs?: number,
): Promise<PluginRunResult> {
  const stored = await readMetric(id);
  return executeMetric({
    dir: stored.dir,
    manifest: stored.manifest,
    secrets,
    ...(timeoutMs !== undefined ? { timeoutMs } : {}),
  });
}

/**
 * The only way a plugin or a connector reaches the network.
 *
 * Extracted so the two execution paths share one implementation rather than
 * two that agree today. This is the security-critical code in the runner —
 * https only, the private-address block, the allowlist, a manual redirect
 * with the host re-checked on every hop, and a response cap — and a second
 * copy of it is a second place for one of those to be forgotten.
 *
 * The redirect handling is the subtle part. `fetch` re-sends request headers
 * across a same-protocol redirect, so a server that 302s to a host outside
 * the allowlist would be handed the user's API key by the runtime, with none
 * of our code involved.
 */
export function allowlistedHttp(options: {
  allowedHosts: string[];
  signal: AbortSignal;
  httpCalls: PluginHttpCall[];
}) {
  return async function http(
    url: string,
    init: { method?: string; headers?: Record<string, string>; body?: string } = {},
  ) {
    let target = url;

    for (let hop = 0; ; hop++) {
      const verdict = checkHost(target, options.allowedHosts);
      if (!verdict.allowed) {
        options.httpCalls.push({
          host: safeHost(target),
          method: init.method ?? "GET",
          status: null,
          ms: 0,
          blocked: true,
        });
        throw new PolicyError(verdict.reason);
      }

      const started = Date.now();
      const response = await fetch(target, {
        method: init.method ?? "GET",
        headers: init.headers,
        body: init.body,
        // Manual, and the host is re-checked on every hop. `fetch` re-sends
        // request headers across a same-protocol redirect, so a server that
        // 302s off-allowlist would otherwise be handed the plugin's API key.
        redirect: "manual",
        signal: options.signal,
      });

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (!location || hop >= MAX_REDIRECTS) throw new PolicyError("too many redirects");
        target = new URL(location, target).toString();
        continue;
      }

      options.httpCalls.push({
        host: safeHost(target),
        method: init.method ?? "GET",
        status: response.status,
        ms: Date.now() - started,
        blocked: false,
      });

      const text = await response.text();
      if (text.length > MAX_RESPONSE_BYTES) {
        throw new PolicyError(`${safeHost(target)} returned more than 4 MB`);
      }

      return {
        ok: response.ok,
        status: response.status,
        headers: Object.fromEntries(response.headers.entries()),
        json: async () => JSON.parse(text) as unknown,
        text: async () => text,
      };
    }
  };
}
