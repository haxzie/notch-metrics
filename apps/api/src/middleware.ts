import { createMiddleware } from "hono/factory";
import { HTTPException } from "hono/http-exception";
import { createAuth } from "./lib/auth.ts";
import { createDb, type Database } from "./lib/db.ts";
import { identityFromBearer, type Identity } from "./lib/identity.ts";
import { billingState, hasAccess } from "./lib/entitlement.ts";
import { take } from "./lib/rate-limit.ts";
import type { Env } from "./env.ts";

export interface Variables {
  db: Database;
  identity: Identity;
}

export type AppContext = { Bindings: Env; Variables: Variables };

export const withDb = createMiddleware<AppContext>(async (c, next) => {
  c.set("db", createDb(c.env));
  await next();
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
    return next();
  }

  const auth = createAuth(c.env);
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  if (!session?.user?.id) {
    throw new HTTPException(401, { message: "Sign in to continue." });
  }

  c.set("identity", { userId: session.user.id, kind: "session", deviceTokenId: null });
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
