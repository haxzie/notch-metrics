import { createMiddleware } from "hono/factory";
import { HTTPException } from "hono/http-exception";
import { createAuth } from "./lib/auth.ts";
import { createDb, type Database } from "./lib/db.ts";
import { identityFromBearer, type Identity } from "./lib/identity.ts";
import { billingState, hasAccess } from "./lib/entitlement.ts";
import { take } from "./lib/rate-limit.ts";
import { RequestTelemetry, requestIdFrom } from "./lib/telemetry.ts";
import type { Env } from "./env.ts";

export interface Variables {
  db: Database;
  identity: Identity;
  telemetry: RequestTelemetry;
}

export type AppContext = { Bindings: Env; Variables: Variables };

export const withDb = createMiddleware<AppContext>(async (c, next) => {
  c.set("db", createDb(c.env));
  await next();
});

/**
 * One structured line per request, and an id to quote when asking about it.
 *
 * Outermost, so the line is emitted whatever happens below — including the
 * 500 from `onError`, which is the request most worth having a record of.
 * Before this the only trace of a successful request was a trace event with
 * a method and a status on it, which says a request happened and nothing
 * about who made it, which route served it, or where the time went.
 *
 * `routePath` rather than the URL: Hono knows the pattern that matched, so
 * `/v1/integrations/:id` arrives already grouped and with no id in it. The
 * URL would need masking — `/v1/link/:token` carries a live single-use
 * credential — and would still group badly.
 */
export const withTelemetry = createMiddleware<AppContext>(async (c, next) => {
  const ray = c.req.header("cf-ray") ?? null;
  const telemetry = new RequestTelemetry(requestIdFrom(c.req.raw.headers, ray));
  c.set("telemetry", telemetry);
  // Set before `next()` so it is present on an error response too, which is
  // exactly the response somebody will be quoting back.
  c.header("x-request-id", telemetry.requestId);

  try {
    await next();
  } finally {
    const cf = c.req.raw.cf as { colo?: string } | undefined;
    telemetry.finish({
      method: c.req.method,
      // `routePath` is "/*" when nothing matched; the raw path is safe to
      // name here because no route claimed it, so no token reached it.
      route: c.req.routePath === "/*" ? "(unmatched)" : c.req.routePath,
      status: c.res.status,
      colo: cf?.colo ?? null,
    });
  }
});

/**
 * Accepts either a Better Auth session cookie or a device bearer token.
 *
 * The Mac app only ever has the latter and the web dashboard only ever the
 * former, so every shared route would otherwise need two variants.
 */
export const authenticate = createMiddleware<AppContext>(async (c, next) => {
  const db = c.get("db");

  const bearer = await identityFromBearer(db, c.req.header("authorization") ?? null);
  if (bearer) {
    c.set("identity", bearer);
    c.get("telemetry")?.identify({ userId: bearer.userId, authKind: bearer.kind });
    return next();
  }

  const auth = createAuth(c.env);
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  if (!session?.user?.id) {
    throw new HTTPException(401, { message: "Sign in to continue." });
  }

  c.set("identity", { userId: session.user.id, kind: "session", deviceTokenId: null });
  c.get("telemetry")?.identify({ userId: session.user.id, authKind: "session" });
  await next();
});

/** Session cookie only. For anything a stolen device token must not be able to do. */
export const sessionOnly = createMiddleware<AppContext>(async (c, next) => {
  if (c.get("identity").kind !== "session") {
    throw new HTTPException(403, { message: "This action must be done on the web." });
  }
  await next();
});

/** 402 with a machine-readable reason the notch renders as an upsell. */
export const requireAccess = createMiddleware<AppContext>(async (c, next) => {
  const state = await billingState(c.get("db"), c.get("identity").userId);
  // Free: this request already paid for the query.
  c.get("telemetry")?.identify({ plan: state.plan ?? null });
  if (!hasAccess(state)) {
    return c.json(
      { code: "SUBSCRIPTION_REQUIRED", message: "Your trial has ended.", billing: state },
      402,
    );
  }
  await next();
});

export function rateLimited(options: {
  limit: number;
  windowSeconds: number;
  by?: (identity: Identity) => string;
}) {
  return createMiddleware<AppContext>(async (c, next) => {
    const identity = c.get("identity");
    const subject = options.by
      ? options.by(identity)
      : identity.kind === "device" && identity.deviceTokenId
        ? `device:${identity.deviceTokenId}`
        : `user:${identity.userId}`;

    const result = await take(c.get("db"), subject, options.limit, options.windowSeconds);
    if (!result.allowed) {
      return c.json({ code: "RATE_LIMITED", message: "Slow down a moment." }, 429, {
        "retry-after": String(result.retryAfterSeconds),
      });
    }
    await next();
  });
}

/** For unauthenticated routes, keyed on a hash of the IP rather than the IP. */
export function rateLimitedByIp(limit: number, windowSeconds: number) {
  return createMiddleware<AppContext>(async (c, next) => {
    const ip = c.req.header("cf-connecting-ip") ?? "unknown";
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip));
    const subject = `ip:${[...new Uint8Array(digest).slice(0, 8)]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}`;

    const result = await take(c.get("db"), subject, limit, windowSeconds);
    if (!result.allowed) {
      return c.json({ code: "RATE_LIMITED", message: "Slow down a moment." }, 429, {
        "retry-after": String(result.retryAfterSeconds),
      });
    }
    await next();
  });
}
