/**
 * Ships the API Worker's trace events to Axiom.
 *
 * A Tail Worker rather than a `fetch` from inside the API: tail events are
 * delivered out of band, after the producing request has already answered, so
 * a slow or dead Axiom costs a user nothing. Logging from the request path
 * would put a third party's availability inside every response — and the
 * repository's rule against vendor SDKs in the Worker rules out the other
 * obvious way to do this. There is no SDK here either; Axiom's ingest API is
 * one POST.
 *
 * Logpush can do the same job with no code at all. It is the right choice if
 * raw trace events are enough. This exists because they are not: our console
 * lines are JSON objects, and Logpush would deliver them as strings inside
 * `Logs[].message[]` for Axiom to re-parse. Flattening here is what makes
 * `scope`, `subsystem` and the sweep counts queryable as fields.
 */

export interface Env {
  /** Dataset name, e.g. `notch-api`. */
  AXIOM_DATASET: string;
  /** `https://api.axiom.co`, or `https://api.eu.axiom.co` for an EU org. */
  AXIOM_API_URL?: string;
  /** Ingest-scoped API token. A secret — never a var. */
  AXIOM_TOKEN?: string;
}

interface TailLog {
  timestamp: number;
  level: string;
  message: unknown;
}

interface TailException {
  timestamp: number;
  name: string;
  message: unknown;
}

/** `FetchEventInfo` for a fetch, and null for a cron or an alarm. */
interface TailEventInfo {
  request?: { url?: string; method?: string };
  response?: { status?: number };
}

interface TailItem {
  scriptName?: string | null;
  outcome?: string;
  eventTimestamp?: number | null;
  event?: TailEventInfo | null;
  logs?: TailLog[];
  exceptions?: TailException[];
}

/** One row in Axiom. `_time` is Axiom's own field; everything else is ours. */
interface AxiomEvent extends Record<string, unknown> {
  _time: string;
}

/**
 * Axiom accepts a large body, but a Tail Worker has a CPU and memory budget
 * and a retry costs the whole batch. Splitting keeps one noisy tick from
 * losing the quiet ones alongside it.
 */
const MAX_EVENTS_PER_REQUEST = 500;

/** Enough to read a stack trace, not enough for one line to dominate a batch. */
const MAX_MESSAGE_CHARS = 8_000;

function isoTime(value: number | null | undefined): string {
  // A tail item can arrive without a timestamp. Our own clock is a better
  // answer than letting Axiom stamp it at ingest, which can be a minute out.
  return new Date(typeof value === "number" && value > 0 ? value : Date.now()).toISOString();
}

function truncate(value: string): string {
  return value.length > MAX_MESSAGE_CHARS ? `${value.slice(0, MAX_MESSAGE_CHARS - 1)}…` : value;
}

/**
 * Turns the arguments of one `console` call into fields.
 *
 * `logError` and `logInfo` emit a single JSON object, so the common case is
 * one argument that parses — and its keys become top-level fields, which is
 * the whole point of this Worker. Anything else (a bare string, several
 * arguments, a stray `console.log` from a dependency) is kept as `message`
 * rather than dropped: an unstructured line is still evidence.
 */
export function fieldsFromMessage(message: unknown): Record<string, unknown> {
  const parts = Array.isArray(message) ? message : [message];

  if (parts.length === 1 && typeof parts[0] === "string") {
    try {
      const parsed: unknown = JSON.parse(parts[0]);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // Not JSON. Falls through to the string below.
    }
  }

  return {
    message: truncate(
      parts
        .map((part) => (typeof part === "string" ? part : safeStringify(part)))
        .join(" ")
        .trim(),
    ),
  };
}

function safeStringify(value: unknown): string {
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    // A circular object, or one with a throwing getter. The type is still
    // worth more than nothing.
    return Object.prototype.toString.call(value);
  }
}

/**
 * Flattens a batch of trace events into one Axiom event per log line, plus
 * one per exception and one per invocation.
 *
 * One row per line rather than per invocation, because a line is what you
 * filter on. The invocation row is what remains when a request logged nothing
 * — it is how an `exceededCpu` or a `canceled` outcome stays visible.
 */
export function toAxiomEvents(items: TailItem[]): AxiomEvent[] {
  const events: AxiomEvent[] = [];

  for (const item of items) {
    const base = {
      worker: item.scriptName ?? "unknown",
      outcome: item.outcome ?? "unknown",
    };
    const invocationTime = isoTime(item.eventTimestamp);

    for (const log of item.logs ?? []) {
      events.push({
        _time: isoTime(log.timestamp),
        ...base,
        kind: "log",
        level: log.level,
        ...fieldsFromMessage(log.message),
      });
    }

    for (const exception of item.exceptions ?? []) {
      events.push({
        _time: isoTime(exception.timestamp),
        ...base,
        kind: "exception",
        level: "error",
        // The thrown error's own type and text. These are the ones workerd
        // caught rather than anything we logged, so they have no `scope`.
        error: exception.name,
        message: truncate(
          typeof exception.message === "string"
            ? exception.message
            : safeStringify(exception.message),
        ),
      });
    }

    // Always, even for a clean invocation that logged nothing: this is the
    // row that makes "how many cron ticks ran today" answerable, and the only
    // trace of an invocation killed before it could log. For a fetch it is
    // also the HTTP log — which is the entire value of this for `notch-web`,
    // a Next.js site that barely calls `console` at all.
    const request = item.event?.request;
    const path = safePath(request?.url);
    events.push({
      _time: invocationTime,
      ...base,
      kind: "invocation",
      ...(request?.method ? { method: request.method } : {}),
      ...(path ? { path } : {}),
      ...(typeof item.event?.response?.status === "number"
        ? { status: item.event.response.status }
        : {}),
    });
  }

  return events;
}

/**
 * A request path with everything secret taken out of it.
 *
 * The query string goes entirely — an OAuth callback carries `code` and
 * `state` there — and every path segment that is not plainly a route word is
 * replaced. That rule is not cosmetic: a connect link is
 * `/connect/<randomToken(32)>`, a single-use credential that completes
 * somebody's OAuth flow, and shipping it to a log with thirty-day retention
 * would put live secrets somewhere they outlive their own expiry.
 *
 * Route words are lowercase and short — `connect`, `integrations`,
 * `llms.txt`, and the blog slugs that are the whole reason to want paths at
 * all. Our ids carry an underscore (`int_a1b2…`) and `randomToken` is
 * base64url, so both fail the test on character class as well as on length.
 */
export function safePath(url: string | undefined): string | null {
  if (!url) return null;
  let pathname: string;
  try {
    pathname = new URL(url).pathname;
  } catch {
    return null;
  }

  return (
    pathname
      .split("/")
      .map((segment) =>
        segment === "" || (/^[a-z0-9][a-z0-9.-]*$/.test(segment) && segment.length <= 32)
          ? segment
          : ":x",
      )
      .join("/") || "/"
  );
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Axiom's ingest endpoint for one dataset.
 *
 * `/v1/datasets/<name>/ingest`, not `/v1/ingest/<name>` — the latter is what
 * one of Axiom's own overview pages shows, and it answers
 * `404 path ... was not found`, which reads like a missing dataset rather
 * than a wrong URL. Exported so a test pins the shape; getting it wrong is
 * invisible until somebody notices the dataset is empty.
 */
export function ingestUrl(env: Env): string {
  const base = (env.AXIOM_API_URL ?? "https://api.axiom.co").replace(/\/+$/, "");
  return `${base}/v1/datasets/${encodeURIComponent(env.AXIOM_DATASET)}/ingest`;
}

async function ship(env: Env, events: AxiomEvent[]): Promise<void> {
  if (events.length === 0) return;
  if (!env.AXIOM_TOKEN) {
    // Not configured — a preview deployment, or a `wrangler dev` without the
    // secret. Silent on purpose: a warning per invocation from the thing that
    // carries warnings is its own kind of outage.
    return;
  }

  const url = ingestUrl(env);

  for (const batch of chunk(events, MAX_EVENTS_PER_REQUEST)) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.AXIOM_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(batch),
    });

    if (!response.ok) {
      // Deliberately not retried. A Tail Worker that retries a rejected
      // batch turns a bad token into a request amplifier against Axiom, and
      // the events it is retrying are already a minute stale. The body is
      // read so a 401 says "unauthorised" rather than only "400".
      const detail = await response.text().catch(() => "");
      throw new Error(`axiom ingest ${response.status}: ${detail.slice(0, 200)}`);
    }
  }
}

export default {
  async tail(events: TailItem[], env: Env, ctx: ExecutionContext): Promise<void> {
    // `waitUntil` rather than awaiting: the handler returning promptly is what
    // keeps a slow Axiom from backing up the producer's tail queue.
    ctx.waitUntil(
      ship(env, toAxiomEvents(events)).catch((error: unknown) => {
        // The one place a bare console line is right. This Worker is the
        // thing that ships console lines, so its own failure has nowhere
        // else to go — it lands in Workers Logs, where `wrangler tail
        // notch-logs` will find it.
        console.error(`[logs.ship] ${error instanceof Error ? error.message : String(error)}`);
      }),
    );
  },
};
