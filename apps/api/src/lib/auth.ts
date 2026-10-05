import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { schema } from "@notch/db";
import { createDb } from "./db.ts";
import { required, type Env } from "../env.ts";

/**
 * Better Auth, constructed per request.
 *
 * It cannot be a module-scope singleton: the D1 binding only exists on `env`,
 * which only exists inside a request. Construction is cheap.
 */
export function createAuth(env: Env) {
  return betterAuth({
    database: drizzleAdapter(createDb(env), { provider: "sqlite", schema }),
    secret: required(env, "BETTER_AUTH_SECRET"),
    baseURL: env.API_URL,
    basePath: "/api/auth",
    trustedOrigins: [env.APP_URL, "http://localhost:3000"],

    user: {
      additionalFields: {
        // `input: false` on every one of these. They are set by the server —
        // by signup, by the Dodo webhook, by PATCH /v1/me — and a field that
        // accepts client input is a field where a user can set their own plan.
        plan: { type: "string", defaultValue: "trial", input: false },
        timezone: { type: "string", defaultValue: "UTC", input: false },
        preferredCurrency: { type: "string", defaultValue: "USD", input: false },
        trialEndsAt: { type: "date", required: false, input: false },
      },
    },

    emailAndPassword: { enabled: false },

    socialProviders: env.GOOGLE_CLIENT_ID
      ? {
          google: {
            clientId: required(env, "GOOGLE_CLIENT_ID"),
            clientSecret: required(env, "GOOGLE_CLIENT_SECRET"),
          },
        }
      : {},

    session: {
      expiresIn: 60 * 60 * 24 * 30,
      updateAge: 60 * 60 * 24,
      cookieCache: { enabled: true, maxAge: 5 * 60 },
    },

    advanced: {
      // Deliberately off. Chrome silently discards a Set-Cookie carrying a
      // dotted domain on `localhost`, so turning this on for production parity
      // makes every local request look signed out with no error anywhere.
      // apps/web and apps/api share `localhost` (cookies ignore the port), so
      // one login already covers both in development.
      crossSubDomainCookies: { enabled: false },
      defaultCookieAttributes: { sameSite: "lax", secure: !env.API_URL.includes("localhost") },
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;
