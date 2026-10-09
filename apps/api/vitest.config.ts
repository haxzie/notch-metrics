import { defineWorkersConfig, readD1Migrations } from "@cloudflare/vitest-pool-workers/config";
import { join } from "node:path";

// The suite runs inside workerd against a real (local) D1, not against a mock.
// Several of the invariants under test — the rate limiter's single-statement
// grant, `onConflictDoNothing` as an idempotency check — are claims about what
// SQLite does with two concurrent statements, and a mock cannot make them.
const migrations = await readD1Migrations(join(import.meta.dirname, "migrations"));

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            BETTER_AUTH_SECRET: "test-secret-not-used-in-production-0000",
            // Valid base64 of exactly 32 bytes. A placeholder that is not valid
            // base64 fails inside atob(), so every crypto test *errors* rather
            // than fails and the message points at the decoder.
            INTEGRATION_KEK_V1: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            INTEGRATION_KEK_V2: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=",
            DODOPAYMENT_WEBHOOK_SECRET: "whsec_dGVzdHNlY3JldGZvcnNpZ25pbmd0ZXN0cw==",
            DODOPAYMENT_API_KEY: "test_key",
            // Blanked, not omitted. Wrangler loads `.dev.vars` for the tests
            // as well as for `wrangler dev`, so a developer with real webhooks
            // configured locally would otherwise post a signup to the team's
            // Slack every time they ran the suite. `lib/slack.ts` treats an
            // empty webhook as "not configured" and does nothing; the tests
            // that exercise it pass their own env in.
            SLACK_WEBHOOK_SIGNUPS: "off",
            SLACK_WEBHOOK_EVENTS: "off",
          },
        },
      },
    },
  },
});
