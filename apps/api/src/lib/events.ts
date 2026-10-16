import { lt } from "drizzle-orm";
import { integrationEvent } from "@notch/db";
import type { Database } from "./db.ts";
import { id } from "./ids.ts";
import { logError, redact } from "./redact.ts";

/** One provider request, as `createHttp`'s `onCall` hook reports it. */
export interface ProviderCall {
  host: string;
  method: string;
  status: number | null;
  ms: number;
}

export interface IntegrationEventInput {
  userId: string;
  integrationId: string;
  kind: "fetch" | "refresh" | "status" | "verify";
  outcome: "ok" | "error" | "skipped";
  metric?: string | null;
  code?: string | null;
  reason?: string | null;
  httpStatus?: number | null;
  durationMs?: number | null;
  calls?: ProviderCall[] | null;
  detail?: string | null;
  /** Ties this row to the request's line in Axiom. Absent from the cron. */
  requestId?: string | null;
}

/**
 * Seven days. Long enough to cover "it broke over the weekend and nobody
 * looked until Monday", short enough that the table stays an operational
 * record rather than something with its own retention policy.
 */
const RETENTION_SECONDS = 7 * 24 * 3600;

/**
 * Provider requests kept per event.
 *
 * A metric that walks pages can make dozens, and the first few plus the
 * failing one are what anybody reads. Keeping all of them would put an
 * unbounded blob in a row written on every fetch.
 */
const MAX_CALLS = 12;

/** A tile's error message can carry a provider's prose. The row is evidence, not a document. */
const MAX_DETAIL = 500;

/**
 * Writes one row describing an attempt.
 *
 * Never throws and never rejects. This is the thing that watches everything
 * else, so a bug in it — a column that drifted, D1 refusing a write — must
 * not be able to turn a working metric fetch into a failed one. A lost log
 * line is a worse diagnosis later; a lost fetch is a blank widget now.
 */
export async function recordEvent(db: Database, input: IntegrationEventInput): Promise<void> {
  try {
    const calls = input.calls?.slice(-MAX_CALLS) ?? null;
    await db.insert(integrationEvent).values({
      id: id("ev"),
      userId: input.userId,
      integrationId: input.integrationId,
      at: Math.floor(Date.now() / 1000),
      kind: input.kind,
      outcome: input.outcome,
      metric: input.metric ?? null,
      code: input.code ?? null,
      reason: input.reason ?? null,
      httpStatus: input.httpStatus ?? null,
      durationMs: input.durationMs ?? null,
      calls: calls && calls.length > 0 ? calls : null,
      // Redacted here as well as at the console boundary. A provider's error
      // prose can quote the request that failed, and unlike a console line
      // this one is kept for a week in a table a support query will read.
      detail: input.detail ? redact(input.detail).slice(0, MAX_DETAIL) : null,
      requestId: input.requestId ?? null,
    });
  } catch (error) {
    logError("events.record", error);
  }
}

/**
 * Collects what the adapter's HTTP layer reports, so a fetch event can say
 * which requests it made and which one decided the outcome.
 *
 * The last call is the interesting one in almost every failure: an adapter
 * throws on the response it could not use, so whatever came back last is the
 * status that produced the error code.
 */
export function callRecorder(): {
  onCall: (call: ProviderCall) => void;
  calls: ProviderCall[];
  lastStatus: () => number | null;
} {
  const calls: ProviderCall[] = [];
  return {
    onCall: (call) => {
      calls.push(call);
    },
    calls,
    lastStatus: () => calls[calls.length - 1]?.status ?? null,
  };
}

/** Opportunistic, from the cron — the same shape as `sweepCache`. */
export async function sweepEvents(db: Database): Promise<void> {
  const cutoff = Math.floor(Date.now() / 1000) - RETENTION_SECONDS;
  await db.delete(integrationEvent).where(lt(integrationEvent.at, cutoff));
}

export const INTERNALS = { RETENTION_SECONDS, MAX_CALLS, MAX_DETAIL };
