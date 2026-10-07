/**
 * The Worker's configuration surface.
 *
 * Hand-written rather than derived from `@notch/env`, because a Worker's
 * configuration is a per-request binding object, not `process.env`. Reading
 * `process.env` here returns `undefined` at deploy time with no error at all,
 * which is the worst shape a configuration bug can take.
 *
 * Non-secret values live in wrangler.jsonc `vars`; secrets are optional here
 * and go through `required()`, which throws a message naming the one that is
 * missing. A Worker that boots and then 500s on one route is much harder to
 * diagnose than one that says `DODOPAYMENT_API_KEY is not set`.
 */
export interface Env {
  DB: D1Database;
  ASSETS_BUCKET: R2Bucket;

  // vars
  APP_URL: string;
  API_URL: string;
  ASSETS_URL: string;
  GITHUB_REPO: string;
  INTEGRATION_KEK_ACTIVE: string;
  DODOPAYMENT_MODE: string;
  DODOPAYMENT_MONTHLY_PRODUCT_ID: string;
  DODOPAYMENT_YEARLY_PRODUCT_ID: string;
  POSTHOG_HOST: string;
  POSTHOG_PROJECT_TOKEN?: string;
  /**
   * Set to a version string to withhold everything newer from the update feed.
   *
   * This is the entire reason the Mac app polls the Worker rather than reading
   * R2 directly: a bad release is pulled back with one `wrangler deploy`, not
   * by waiting out a CDN TTL.
   */
  PINNED_VERSION?: string;

  // secrets
  BETTER_AUTH_SECRET?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  /** Sign-in. Distinct from the connector's client below, on purpose. */
  GITHUB_CLIENT_ID?: string;
  GITHUB_CLIENT_SECRET?: string;
  /**
   * The GitHub *connector's* OAuth client, named by `oauthSecretNames`.
   *
   * A separate app from sign-in: the two have different callback URLs, ask
   * for different scopes, and one is revoked without the other. Sharing a
   * client would mean signing in to Notch Metrics silently granted it
   * repository access.
   */
  OAUTH_GITHUB_CLIENT_ID?: string;
  OAUTH_GITHUB_CLIENT_SECRET?: string;
  INTEGRATION_KEK_V1?: string;
  INTEGRATION_KEK_V2?: string;
  DODOPAYMENT_API_KEY?: string;
  DODOPAYMENT_WEBHOOK_SECRET?: string;
  SENTRY_DSN?: string;

  // test-only, injected by the vitest pool
  TEST_MIGRATIONS?: unknown;
}

export function required<K extends keyof Env>(env: Env, key: K): NonNullable<Env[K]> {
  const value = env[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`${String(key)} is not set`);
  }
  return value as NonNullable<Env[K]>;
}

export function isProduction(env: Env): boolean {
  return !env.API_URL.includes("localhost");
}
