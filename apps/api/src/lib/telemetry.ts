import { logInfo } from "./redact.ts";

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
