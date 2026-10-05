/// <reference types="@cloudflare/vitest-pool-workers" />

import type { Env } from "./src/env.ts";

/**
 * The environment the vitest pool hands to tests.
 *
 * Declared here rather than in a test file so `tsc --noEmit` can resolve the
 * `cloudflare:test` virtual module, which only exists inside the pool at
 * runtime. Extending `Env` is what lets a test pass `env` straight to
 * production code — the pool builds it from wrangler.jsonc plus the extra
 * bindings in vitest.config.ts, so the two really are the same shape.
 */
declare module "cloudflare:test" {
  interface ProvidedEnv extends Env {
    TEST_MIGRATIONS: D1Migration[];
  }
}
