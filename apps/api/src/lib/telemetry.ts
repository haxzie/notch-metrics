import { logInfo, redact } from "./redact.ts";

/**
 * One timed step inside a request.
 *
 * Not distributed tracing — there is one service here, and a span that
 * crossed a process boundary would need propagation nothing else in this
 * system speaks. What this answers is the question that actually comes up:
 * a request took four seconds, which part of it was the provider and which
 * part was us.
 */
export interface Span {
  name: string;
  ms: number;
  /** Absent on success. Present and short when the step threw. */
  error?: string;
}

/**
 * The most spans one request may record.
 *
 * A metric batch fans out across integrations and each one makes several
 * provider calls, so this is unbounded in principle. A log line that grows
 * with a user's widget count is one that eventually gets dropped for size,
 * which loses the whole request rather than the tail of it.
 */
const MAX_SPANS = 40;

/** Bounded and sanitised: this reaches a log field and arrives from a header. */
const MAX_REQUEST_ID = 200;

/** Per body. A metric batch request is a list of widgets; the first few explain it. */
const MAX_BODY_CHARS = 2_000;

/** Bodies larger than this are not read at all, rather than read and truncated. */
const MAX_BODY_BYTES = 128 * 1024;

/**
 * Field names whose values never go to a log store, at any depth.
 *
 * `POST /v1/integrations` carries somebody's Stripe secret key in
 * `credentials`, the OAuth legs carry `code` and `state`, and the desktop
 * handshake carries bearer tokens. A body capture without this is a
 * credential export with a thirty-day retention policy.
 *
 * Matched as a substring on the lowercased key, so `refresh_token`,
 * `clientSecret` and `apiKey` are all caught without listing every spelling
 * every provider uses.
 */
const SECRET_KEYS = [
  "token",
  "secret",
  "password",
  "credential",
  "authorization",
  "apikey",
  "api_key",
  "signature",
  "key",
];

/**
 * `code` and `state` are deliberately *not* on that list.
 *
 * They are OAuth secrets, and the instinct is to add them — but every error
 * body in this API has a `code` (`SUBSCRIPTION_REQUIRED`, `RATE_LIMITED`),
 * and redacting it blanks the single most useful field in a failure capture
 * to protect a value that never reaches here: every OAuth route is on
 * `NO_BODY_ROUTES`, so its body is not read at all. Listing them bought
 * nothing and cost the diagnosis.
 */

function isSecretKey(key: string): boolean {
  const lower = key.toLowerCase();
  return SECRET_KEYS.some((needle) => lower.includes(needle));
}

/**
 * Replaces every secret-looking value in a parsed body, however deep.
 *
 * Returns the shape rather than the content for those fields: knowing that
 * `credentials.api_key` was present and 32 characters long is most of what a
 * body capture was wanted for, and none of the risk.
 */
export function scrub(value: unknown, depth = 0): unknown {
  if (depth > 6) return "[deep]";
  if (Array.isArray(value)) return value.slice(0, 20).map((item) => scrub(item, depth + 1));
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
      out[key] = isSecretKey(key)
        ? `[redacted ${typeof inner === "string" ? `${inner.length} chars` : typeof inner}]`
        : scrub(inner, depth + 1);
    }
    return out;
  }
  // A string that is not under a secret key can still *be* one — a token
  // pasted into a `message`, say — so the pattern-based pass still runs.
  if (typeof value === "string") return redact(value);
  return value;
}

/**
 * A body, parsed and scrubbed, or a bounded string when it is not JSON.
 *
 * Never throws: this runs while logging a request that has already failed,
 * and a second failure here would lose the record of the first.
 */
export function safeBody(raw: string): unknown {
  try {
    return scrub(JSON.parse(raw));
  } catch {
    return redact(raw).slice(0, MAX_BODY_CHARS);
  }
}

export const BODY_LIMITS = { MAX_BODY_CHARS, MAX_BODY_BYTES };

/**
 * Everything known about the request in flight, accumulated as it runs and
 * emitted once at the end.
 *
 * One line per request rather than several, because a line is the unit
 * Axiom groups and filters on — `summarize avg(ms) by route` only works if
 * route and duration are on the same event.
 */
export class RequestTelemetry {
  readonly requestId: string;
  private readonly startedAt = Date.now();
  private readonly spans: Span[] = [];
  private dropped = 0;
  private userId: string | null = null;
  private plan: string | null = null;
  private authKind: string | null = null;
  private errorCode: string | null = null;
  private requestBody: unknown = undefined;
  private responseBody: unknown = undefined;

  constructor(requestId: string) {
    this.requestId = requestId;
  }

  /**
   * Who is asking — by id, and never by name or email.
   *
   * A user id is enough to find somebody in the database when they write in,
   * and it is meaningless to anyone who has not got the database. An email
   * address in a third-party log store is personal data sitting somewhere it
   * was never collected to be, readable by anyone with a query token, for as
   * long as the retention window says. The id does the job the address would
   * have done.
   */
  identify(options: { userId?: string | null; plan?: string | null; authKind?: string | null }) {
    if (options.userId !== undefined) this.userId = options.userId;
    if (options.plan !== undefined) this.plan = options.plan;
    if (options.authKind !== undefined) this.authKind = options.authKind;
  }

  /**
   * The machine-readable reason a request failed — `SUBSCRIPTION_REQUIRED`,
   * `RATE_LIMITED`, `NOT_FOUND`.
   *
   * The single most useful field on a failure and the cheapest: one short
   * string that turns "why is this a 402" into a filter, with none of the
   * exposure of keeping the body it came from.
   */
  fail(code: string | null, request?: unknown, response?: unknown) {
    if (code) this.errorCode = code;
    if (request !== undefined) this.requestBody = request;
    if (response !== undefined) this.responseBody = response;
  }

  /** Records a step that has already been timed — the provider calls, mostly. */
  record(span: Span) {
    if (this.spans.length >= MAX_SPANS) {
      this.dropped += 1;
      return;
    }
    this.spans.push(span);
  }

  /**
   * Times `fn`, recording it either way.
   *
   * The failing step is the one worth timing, so a throw is recorded and
   * rethrown rather than swallowed — telemetry that only describes the happy
   * path describes the requests nobody is investigating.
   */
  async span<T>(name: string, fn: () => Promise<T>): Promise<T> {
    const started = Date.now();
    try {
      const result = await fn();
      this.record({ name, ms: Date.now() - started });
      return result;
    } catch (error) {
      this.record({
        name,
        ms: Date.now() - started,
        error: error instanceof Error ? error.name : "error",
      });
      throw error;
    }
  }

  /** The fields for the request's one log line. */
  finish(outcome: { method: string; route: string; status: number; colo?: string | null }) {
    logInfo("http", {
      requestId: this.requestId,
      method: outcome.method,
      route: outcome.route,
      status: outcome.status,
      ms: Date.now() - this.startedAt,
      ...(this.userId ? { userId: this.userId } : {}),
      ...(this.plan ? { plan: this.plan } : {}),
      ...(this.authKind ? { authKind: this.authKind } : {}),
      ...(outcome.colo ? { colo: outcome.colo } : {}),
      ...(this.errorCode ? { errorCode: this.errorCode } : {}),
      ...(this.requestBody !== undefined ? { requestBody: this.requestBody } : {}),
      ...(this.responseBody !== undefined ? { responseBody: this.responseBody } : {}),
      ...(this.spans.length > 0 ? { spans: this.spans } : {}),
      // Said out loud rather than left as a short list, so a truncated trace
      // is never mistaken for a fast request.
      ...(this.dropped > 0 ? { spansDropped: this.dropped } : {}),
    });
  }
}

/**
 * The id that ties a log line, an `integration_event` row and a support
 * email together.
 *
 * `cf-ray` by preference: Cloudflare already generates one per request, it
 * appears in their own dashboards, and reusing it means our logs and theirs
 * name the same thing. A caller-supplied `x-request-id` wins over it so a
 * client can correlate a retry, but it is bounded and stripped of anything
 * that is not an identifier — it is attacker-controlled and ends up in a log
 * field.
 */
export function requestIdFrom(headers: Headers, ray: string | null): string {
  const supplied = headers.get("x-request-id");
  if (supplied) {
    const clean = supplied.replace(/[^\w.:-]/g, "").slice(0, MAX_REQUEST_ID);
    if (clean.length > 0) return clean;
  }
  return ray ?? crypto.randomUUID();
}
