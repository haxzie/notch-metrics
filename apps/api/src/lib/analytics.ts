import { logError } from "./redact.ts";
import type { Env } from "../env.ts";

/**
 * The PostHog transport. No domain knowledge: `track.ts` decides what an
 * event is called and what belongs on it, and this gets it there.
 *
 * Fetch against the ingestion endpoint rather than `posthog-node`. The SDK
 * exists to buffer, retry and flush on a timer from a long-lived process, and
 * a Worker is none of those things — an isolate can be torn down the moment
 * the response is written, so a buffered event is a lost event. `AGENTS.md`
 * says it directly: no vendor SDK for a handful of POSTs.
 *
 * Nothing here is allowed to affect a request. Every call resolves, never
 * rejects, exactly as `slack.ts` does.
 */

/** One event, in the shape `/batch/` wants it. */
export interface CaptureEvent {
  event: string;
  /** Always a user id. Never an email: see the note in `track.ts`. */
  distinctId: string;
  properties?: Record<string, unknown>;
  /** ISO 8601. Set by the caller so a batch keeps the real ordering. */
  timestamp?: string;
}

/**
 * The most events one call may send.
 *
 * A layout PUT replaces the whole list, so somebody rebuilding their notch
 * from scratch can produce a `widget_added` per tile in one request. The cap
 * keeps that from becoming a payload PostHog rejects whole, which would lose
 * the interesting first few along with the tail.
 */
const MAX_BATCH = 50;

/**
 * Three seconds, for the same reason Slack gets three: this runs inside
 * `waitUntil`, and a hung POST holds the Worker's budget open.
 */
const TIMEOUT_MS = 3_000;

/**
 * Sends a batch, if PostHog is configured.
 *
 * Unconfigured is a no-op rather than an error: that is every test run and any
 * dev stack whose owner does not want their funnel full of fake signups.
 *
 * Always `/batch/`, even for one event. The single-event endpoint takes a
 * different body shape, and carrying two shapes to save a few bytes buys a
 * second thing to get wrong.
 */
export async function capture(env: Env, events: CaptureEvent[]): Promise<void> {
  const token = env.POSTHOG_PROJECT_TOKEN;
  if (!token || events.length === 0) return;

  const batch = events.slice(0, MAX_BATCH).map((e) => ({
    event: e.event,
    // `/batch/` reads `distinct_id` from inside `properties`, unlike the
    // single-event endpoint, which takes it at the top level. Putting it in
    // the wrong place is accepted with a 200 and silently drops the event's
    // identity, which is the worst failure shape available here.
    properties: { ...(e.properties ?? {}), distinct_id: e.distinctId },
    ...(e.timestamp ? { timestamp: e.timestamp } : {}),
  }));

  try {
    const response = await fetch(`${env.POSTHOG_HOST.replace(/\/$/, "")}/batch/`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ api_key: token, historical_migration: false, batch }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!response.ok) {
      // PostHog answers 401 for a bad project token and 400 for a malformed
      // batch. The status is most of the diagnosis.
      logError("analytics", new Error(`PostHog returned ${response.status}`));
    }
  } catch (error) {
    logError("analytics", error);
  }
}

/**
 * The person behind the ids, as a `$identify` event.
 *
 * `$set` is what turns a row of anonymous user ids in PostHog into something
 * you can read: without it every insight is keyed by `usr_...` and nobody can
 * tell who churned. Sent on sign-up and on every sign-in, because a name or a
 * plan changes after the account is created and the last write wins.
 */
export function identifyEvent(user: {
  id: string;
  email: string;
  name?: string | null;
  plan?: string | null;
}): CaptureEvent {
  return {
    event: "$identify",
    distinctId: user.id,
    properties: {
      $set: {
        email: user.email,
        ...(user.name ? { name: user.name } : {}),
        ...(user.plan ? { plan: user.plan } : {}),
      },
    },
  };
}
