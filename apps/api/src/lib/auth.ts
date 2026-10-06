import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { schema } from "@notch/db";
import { createDb } from "./db.ts";
import { TRIAL_DAYS } from "./entitlement.ts";
import { isProduction, required, type Env } from "../env.ts";

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

    // Off in production: Google is the only way in, so there are no
    // passwords to leak, reset or rate-limit.
    //
    // On locally, because the alternative is that nobody can sign in to a
    // dev stack without a Google OAuth client, and `isProduction` reads the
    // Worker's own API_URL rather than a flag someone could set.
    emailAndPassword: { enabled: !isProduction(env) },

    socialProviders: env.GOOGLE_CLIENT_ID
      ? {
          google: {
            clientId: required(env, "GOOGLE_CLIENT_ID"),
            clientSecret: required(env, "GOOGLE_CLIENT_SECRET"),
          },
        }
      : {},

    databaseHooks: {
      user: {
        create: {
          // The only place a trial is granted.
          //
          // `trialEndsAt` has `input: false`, so it cannot be set by the
          // client, and nothing else writes it — without this hook every
          // account is created already expired, `hasAccess` is false from
          // the first request, and the notch never loads a single metric.
          before: async (user) => ({
            data: {
              ...user,
              trialEndsAt: new Date(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000),
            },
          }),
        },
      },
    },

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
