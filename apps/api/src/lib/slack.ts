import { logError } from "./redact.ts";
import type { Env } from "../env.ts";

/**
 * Operational notifications, posted to Slack incoming webhooks.
 *
 * One function for the whole surface: callers describe *what happened* and
 * this decides which channel it belongs in and how it reads. Adding an event
 * is a member of `SlackEvent` plus a case in `render` — the routing, the
 * transport, the timeout and the failure handling are already here.
 *
 * Nothing here is allowed to affect a request. Every call resolves, never
 * rejects, and a Slack outage must never turn into a failed signup.
 */

export type SlackChannel = "signups" | "events";

export type SlackEvent =
  | { kind: "signup"; email: string; name?: string | null; via?: string | null }
  | { kind: "integration_connected"; provider: string; account: string; email: string | null }
  | { kind: "integration_disconnected"; provider: string; account: string; email: string | null }
  | { kind: "integration_broken"; provider: string; account: string; email: string | null }
  | { kind: "custom_app_added"; name: string; appId: string; email: string | null };

/** Which secret holds each channel's webhook. */
const WEBHOOK: Record<SlackChannel, keyof Env> = {
  signups: "SLACK_WEBHOOK_SIGNUPS",
  events: "SLACK_WEBHOOK_EVENTS",
};

/** Slack renders one line per message; these are read at a glance, not studied. */
function render(event: SlackEvent): { channel: SlackChannel; text: string } {
  switch (event.kind) {
    case "signup":
      return {
        channel: "signups",
        text: `:wave: ${[event.email, event.name, event.via].filter(Boolean).join(" · ")}`,
      };
    case "integration_connected":
      return { channel: "events", text: `:link: Connected ${describe(event)}` };
    case "integration_disconnected":
      return { channel: "events", text: `:heavy_minus_sign: Disconnected ${describe(event)}` };
    case "integration_broken":
      return { channel: "events", text: `:warning: Needs reconnecting — ${describe(event)}` };
    // The name first, because it is the only part of this message that is not
    // already known: somebody wrote their own connector and called it that.
    case "custom_app_added":
      return {
        channel: "events",
        text: `:hammer_and_wrench: Custom app — ${[event.name, event.appId, event.email]
          .filter(Boolean)
          .join(" · ")}`,
      };
  }
}

function describe(event: { provider: string; account: string; email: string | null }): string {
  return [event.provider, event.account, event.email].filter(Boolean).join(" · ");
}

/**
 * Posts one event, if its channel is configured.
 *
 * Unconfigured is a no-op rather than an error: that is the state of every
 * test run and of any dev stack whose owner did not want their Slack filling
 * up, and neither should have to special-case a notification.
 *
 * Callers with an `ExecutionContext` should hand the returned promise to
 * `waitUntil` so the user is not waiting on Slack; callers without one (the
 * cron, the credential refresher) can await it, since every path that reaches
 * here is a rare transition rather than a hot one.
 */
export async function notify(env: Env, event: SlackEvent): Promise<void> {
  const { channel, text } = render(event);
  const url = env[WEBHOOK[channel]];
  if (typeof url !== "string" || url === "") return;

  // These messages carry user email addresses. A webhook secret mistyped into
  // the wrong variable — or pointed somewhere else entirely — would post them
  // to whoever owns that host, so the destination is checked rather than
  // trusted.
  if (!isSlackWebhook(url)) {
    logError(`slack.${channel}`, new Error("webhook is not a hooks.slack.com URL; not posting"));
    return;
  }

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text }),
      // Three seconds. Slack is not on the critical path of anything here,
      // and a hung POST inside `waitUntil` holds the Worker's budget open.
      signal: AbortSignal.timeout(3_000),
    });
    if (!response.ok) {
      // Slack answers 404 for a revoked webhook and 410 for a deleted one.
      // The status is the whole diagnosis, and the body is "invalid_token".
      logError(`slack.${channel}`, new Error(`Slack returned ${response.status}`));
    }
  } catch (error) {
    logError(`slack.${channel}`, error);
  }
}

function isSlackWebhook(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && parsed.hostname === "hooks.slack.com";
  } catch {
    return false;
  }
}
