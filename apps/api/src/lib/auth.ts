import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { schema } from "@notch/db";
import { createDb } from "./db.ts";
import { sendWelcome } from "./email.ts";
import { TRIAL_DAYS } from "./entitlement.ts";
import { loadUser } from "./identity.ts";
import { track } from "./track.ts";
import { isProduction, required, type Env } from "../env.ts";

/**
 * Better Auth, constructed per request.
 *
 * It cannot be a module-scope singleton: the D1 binding only exists on `env`,
 * which only exists inside a request. Construction is cheap.
 *
 * `waitUntil` is how the signup notification and the welcome email stay off
 * the critical path. It is optional because most callers only ever read a
 * session, which fires no hooks — without one they are simply awaited.
 */
export function createAuth(env: Env, waitUntil?: (promise: Promise<unknown>) => void) {
  /**
   * Whether this request is the one that created the account.
   *
   * Signing up also creates a session, so both hooks below fire on the same
   * request and the naive version reports every signup as a signin too, which
   * quietly inflates the top of the funnel by exactly the number of new users.
   * A closure variable is enough to tell them apart because `createAuth` is
   * per request: the two hooks that read it are always the same invocation.
   */
  let signedUpThisRequest = false;

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

    // Built from whichever client ids are present rather than from a flag:
    // a provider listed here without a secret fails at the redirect, which
    // reads as a broken button rather than as missing configuration.
    socialProviders: {
      ...(env.GOOGLE_CLIENT_ID && {
        google: {
          clientId: required(env, "GOOGLE_CLIENT_ID"),
          clientSecret: required(env, "GOOGLE_CLIENT_SECRET"),
        },
      }),
      ...(env.GITHUB_CLIENT_ID && {
        github: {
          clientId: required(env, "GITHUB_CLIENT_ID"),
          clientSecret: required(env, "GITHUB_CLIENT_SECRET"),
        },
      }),
    },

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
          // Every account is created through this hook, whichever provider
          // it came in by — which is why the notification and the welcome
          // email hang off it rather than off a route. It fires once per
          // account, which is what keeps a returning user from being
          // welcomed twice.
          after: async (user) => {
            signedUpThisRequest = true;
            const posted = Promise.all([
              track(env, {
                kind: "signed_up",
                userId: user.id,
                email: user.email,
                name: user.name,
              }),
              sendWelcome(env, { email: user.email, name: user.name }),
            ]);
            if (waitUntil) waitUntil(posted);
            else await posted;
          },
        },
      },

      session: {
        create: {
          /**
           * Every sign-in, by any provider, and nothing else: a session row is
           * written once per sign-in and the cookie cache serves the rest of
           * the month from memory without touching this.
           *
           * Loads the user because a session row carries an id and no address,
           * and `$identify` without an address leaves PostHog full of people
           * called `usr_01h...`. One indexed read on a path that runs once per
           * sign-in, not once per request.
           */
          after: async (session) => {
            if (signedUpThisRequest) return;
            const posted = (async () => {
              const owner = await loadUser(createDb(env), session.userId);
              if (!owner) return;
              await track(env, {
                kind: "signed_in",
                userId: owner.id,
                email: owner.email,
                name: owner.name,
              });
            })();
            if (waitUntil) waitUntil(posted);
            else await posted;
          },
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
