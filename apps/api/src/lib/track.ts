import { capture, identifyEvent, type CaptureEvent } from "./analytics.ts";
import { loadUser } from "./identity.ts";
import { notify, type SlackEvent } from "./slack.ts";
import type { Database } from "./db.ts";
import type { Env } from "../env.ts";

/**
 * One product event, and the one place that says what happens to it.
 *
 * Every interesting thing a user does is described here once, and `track`
 * decides which destinations it reaches. The alternative — a `notify` call
 * for Slack and a `capture` call for PostHog at each site — is two lines that
 * have to be kept in step at a dozen places, and the second one is the one
 * that gets forgotten when a third destination shows up.
 *
 * `userId` is on every variant because it is the `distinct_id`, and an event
 * PostHog cannot attribute is a row in a funnel nobody can follow.
 *
 * **`email` is for Slack, not for PostHog.** `lib/telemetry.ts` refuses to put
 * an address in the log store and explains why; the same reasoning does not
 * carry over wholesale, because an analytics tool whose users are all called
 * `usr_01h...` cannot answer the question it was bought for. The compromise:
 * the address goes to PostHog only inside `$identify`'s `$set`, where it is
 * one person-shaped record, and never as a property on an ordinary event.
 */
export type ProductEvent =
  | { kind: "signed_up"; userId: string; email: string; name?: string | null; via?: string | null }
  | { kind: "signed_in"; userId: string; email: string; name?: string | null; via?: string | null }
  | {
      kind: "integration_connected";
      userId: string;
      email: string | null;
      provider: string;
      account: string;
      integrationId?: string;
    }
  | {
      kind: "integration_disconnected";
      userId: string;
      email: string | null;
      provider: string;
      account: string;
      integrationId?: string;
    }
  | {
      kind: "integration_broken";
      userId: string;
      email: string | null;
      provider: string;
      account: string;
      integrationId?: string;
    }
  /**
   * A custom metric of the user's own appearing in, or leaving, their layout.
   *
   * This is as close to "added a custom app" as the server can honestly get.
   * A custom connector is registered on the user's Mac, under
   * `~/Library/Application Support/NotchMetrics/connectors`, and never touches
   * this API — so the first and only server-visible moment is the layout PUT
   * that puts a tile for it in the notch. `name` is the widget's own title,
   * which is what the user typed and therefore what is worth reading in Slack.
   */
  | {
      kind: "custom_app_added";
      userId: string;
      email: string | null;
      appId: string;
      name: string;
      customMetricId: string | null;
    }
  | {
      kind: "custom_app_removed";
      userId: string;
      email: string | null;
      appId: string;
      name: string;
      customMetricId: string | null;
    }
  | {
      kind: "widget_added";
      userId: string;
      widgetKind: string;
      appId: string;
      metric: string | null;
      size: string;
      chart: string;
      range: string;
    }
  | {
      kind: "widget_removed";
      userId: string;
      widgetKind: string;
      appId: string;
      metric: string | null;
    }
  | { kind: "layout_saved"; userId: string; widgets: number; rows: number; revision: number }
  | {
      kind: "subscription_changed";
      userId: string;
      email: string | null;
      status: string;
      dodoEvent: string;
      plan: string | null;
    };

/** The PostHog event name for each kind. Past tense, snake case, stable. */
const EVENT_NAME: Record<ProductEvent["kind"], string> = {
  signed_up: "user_signed_up",
  signed_in: "user_signed_in",
  integration_connected: "integration_connected",
  integration_disconnected: "integration_disconnected",
  integration_broken: "integration_broken",
  custom_app_added: "custom_app_added",
  custom_app_removed: "custom_app_removed",
  widget_added: "widget_added",
  widget_removed: "widget_removed",
  layout_saved: "layout_saved",
  subscription_changed: "subscription_changed",
};

/**
 * The properties PostHog gets, which is everything on the event except the
 * three fields that are not properties.
 *
 * `kind` comes off because the event name already carries it. `email` and
 * `name` come off for the reason in the type's docs: they reach PostHog once,
 * inside `$identify`'s `$set`, and an address repeated onto every event is a
 * second copy of the same personal data in a place no query needs it.
 *
 * Built by subtraction rather than by listing each variant's fields, so a
 * property added to a variant above arrives in PostHog without a second edit
 * here — the failure mode of the explicit version is a field that exists in
 * the code and never in a chart.
 */
function properties(event: ProductEvent): Record<string, unknown> {
  const {
    kind: _kind,
    email: _email,
    name: _name,
    ...rest
  } = event as ProductEvent & { email?: unknown; name?: unknown };
  return rest;
}

/**
 * The Slack message for an event, or null for the ones no human needs to see.
 *
 * Sign-ins and widget edits are deliberately absent. They are the two highest
 * volume events here, and a channel that posts every one of them is a channel
 * that gets muted, taking the signups with it.
 */
function slackFor(event: ProductEvent): SlackEvent | null {
  switch (event.kind) {
    case "signed_up":
      return { kind: "signup", email: event.email, name: event.name, via: event.via };
    case "integration_connected":
    case "integration_disconnected":
    case "integration_broken":
      return {
        kind: event.kind,
        provider: event.provider,
        account: event.account,
        email: event.email,
      };
    case "custom_app_added":
      return { kind: "custom_app_added", name: event.name, appId: event.appId, email: event.email };
    default:
      return null;
  }
}

/**
 * Sends one event, or a batch of them, everywhere it belongs.
 *
 * Resolves on every path. A dead Slack or a rejected PostHog batch must never
 * be the reason a user could not connect Stripe, so the whole fan-out is
 * wrapped the way each transport already wraps itself.
 *
 * Callers with an `ExecutionContext` should pass `waitUntil` so the user is
 * not waiting on either service; the cron and the webhook can await it, since
 * nothing on those paths is latency-sensitive.
 */
export function track(
  env: Env,
  events: ProductEvent | ProductEvent[],
  waitUntil?: (promise: Promise<unknown>) => void,
): Promise<void> {
  const list = Array.isArray(events) ? events : [events];
  if (list.length === 0) return Promise.resolve();

  // One timestamp for the whole batch. A layout PUT emits a dozen events from
  // a single request, and they really did happen at the same moment.
  const timestamp = new Date().toISOString();

  const captures: CaptureEvent[] = [];
  for (const event of list) {
    // Identity first, so PostHog knows who this is before the event that
    // mentions them arrives. Within one batch the order is preserved.
    if (event.kind === "signed_up" || event.kind === "signed_in") {
      captures.push(identifyEvent({ id: event.userId, email: event.email, name: event.name }));
    }
    captures.push({
      event: EVENT_NAME[event.kind],
      distinctId: event.userId,
      properties: properties(event),
      timestamp,
    });
  }

  const sent = Promise.all([
    capture(env, captures),
    ...list.map((event) => {
      const message = slackFor(event);
      return message ? notify(env, message) : Promise.resolve();
    }),
  ]).then(() => undefined);

  if (waitUntil) {
    waitUntil(sent);
    return Promise.resolve();
  }
  return sent;
}

/**
 * The one connection transition worth hearing about: a working one going dead.
 *
 * Takes the row's *previous* status so it fires on the edge rather than on the
 * state. A revoked key fails on every poll, and reporting on the state would
 * mean a message every five minutes until somebody reconnects it.
 *
 * Looks the email up itself: all three callers are deep in the refresh path,
 * where the user row is not otherwise needed, and this runs only on the
 * transition.
 *
 * Lives here rather than in `slack.ts`, where it used to: it now has two
 * destinations, and `slack.ts` importing this module to reach them would close
 * an import cycle.
 */
export async function trackBroken(
  env: Env,
  db: Database,
  previousStatus: string,
  row: {
    id?: string;
    provider: string;
    label: string;
    accountLabel: string | null;
    userId: string;
  },
): Promise<void> {
  if (previousStatus === "auth_failed") return;
  const owner = await loadUser(db, row.userId);
  await track(env, {
    kind: "integration_broken",
    userId: row.userId,
    email: owner?.email ?? null,
    provider: row.provider,
    account: row.accountLabel ?? row.label,
    ...(row.id ? { integrationId: row.id } : {}),
  });
}
