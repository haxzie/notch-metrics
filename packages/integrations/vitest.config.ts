import { defineConfig } from "vitest/config";

// Node pool, no network. Adapters are pure given a `http` implementation, and
// the fixtures are real captured responses with the keys scrubbed.
export default defineConfig({ test: { include: ["test/**/*.test.ts"] } });
