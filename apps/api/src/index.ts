import { Hono } from "hono";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { createAuth } from "./lib/auth.ts";
import { withDb, withTelemetry, type AppContext } from "./middleware.ts";
import { billing } from "./routes/billing.ts";
import { connect } from "./routes/connect.ts";
import { connectors } from "./routes/connectors.ts";
import { link } from "./routes/link.ts";
import { desktop } from "./routes/desktop.ts";
import { integrations } from "./routes/integrations.ts";
import { me } from "./routes/me.ts";
import { metrics } from "./routes/metrics.ts";
import { providers } from "./routes/providers.ts";
import { updates } from "./routes/updates.ts";
import { widgets } from "./routes/widgets.ts";
import { notifications } from "./routes/notifications.ts";
import { dodoWebhook } from "./routes/webhooks/dodo.ts";
import { scheduled } from "./cron.ts";
import { logError } from "./lib/redact.ts";
import type { Env } from "./env.ts";

const app = new Hono<AppContext>();

// First, so every request below it is accounted for — including the ones
// that never reach a route.
app.use("*", withTelemetry);
app.use("*", withDb);

app.use(
  "*",
  cors({
    // Echoed, never `*`. A browser refuses to send credentials to a wildcard
    // origin, so `*` would sign out every dashboard user with no error that
    // points at CORS.
    origin: (origin, c) => {
      const allowed = [c.env.APP_URL, "http://localhost:3000"];
      return allowed.includes(origin) ? origin : allowed[0]!;
    },
    credentials: true,
    allowHeaders: ["content-type", "authorization", "if-none-match"],
    // `x-request-id` so the dashboard can quote the id of a request that
    // failed. A header the browser cannot read is one a bug report cannot
    // include.
    exposeHeaders: ["etag", "retry-after", "x-request-id"],
  }),
);

// `waitUntil` so the signup notification posts after the response rather
// than inside it — Slack being slow must not make signing up slow.
app.on(["GET", "POST"], "/api/auth/*", (c) =>
  createAuth(c.env, (promise) => c.executionCtx.waitUntil(promise)).handler(c.req.raw),
);

app.route("/v1/me", me);
app.route("/v1/desktop", desktop);
app.route("/v1/providers", providers);
app.route("/v1/connectors", connectors);
app.route("/v1/connect", connect);
app.route("/v1/link", link);
app.route("/v1/integrations", integrations);
app.route("/v1/metrics", metrics);
app.route("/v1/widgets", widgets);
app.route("/v1/notifications", notifications);
app.route("/v1/billing", billing);
app.route("/v1/updates", updates);
app.route("/v1/webhooks/dodo", dodoWebhook);

app.get("/health", (c) => c.json({ ok: true }));

app.notFound((c) => c.json({ code: "NOT_FOUND", message: "No such endpoint." }, 404));

app.onError((error, c) => {
  if (error instanceof HTTPException) {
    return c.json({ code: "ERROR", message: error.message }, error.status);
  }
  // With the request id, so the 500 somebody is complaining about and the
  // line describing it can be found as one thing.
  logError(`unhandled.${c.get("telemetry")?.requestId ?? "unknown"}`, error);
  // Generic on purpose. A thrown message here routinely names a missing secret
  // — `required()` is built to do exactly that — and that is for the logs.
  return c.json({ code: "ERROR", message: "Something went wrong." }, 500);
});

export default {
  fetch: app.fetch,
  scheduled: (_controller: ScheduledController, env: Env, ctx: ExecutionContext) => {
    ctx.waitUntil(scheduled(env));
  },
} satisfies ExportedHandler<Env>;
