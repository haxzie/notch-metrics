import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./src/schema.ts",
  /**
   * Migrations are written into apps/api, not into this package.
   *
   * `wrangler d1 migrations apply` resolves `migrations_dir` relative to
   * wrangler.jsonc, so a migrations directory anywhere else is a directory
   * wrangler will not find — and it reports "no migrations to apply" rather
   * than an error, which reads as success.
   */
  out: "../../apps/api/migrations",
});
