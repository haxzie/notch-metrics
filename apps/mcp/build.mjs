/**
 * Bundles the server into one file with the workspace packages inlined.
 *
 * The published artefact has to run under `npx` on a machine that has never
 * heard of this monorepo, so `@notch/*` must not survive as an import — they
 * are `workspace:*` and would resolve to nothing.
 */
import { build } from "esbuild";
import { chmod } from "node:fs/promises";

const outfile = "dist/index.mjs";

await build({
  entryPoints: ["src/index.ts"],
  outfile,
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node22",
  // Everything with a real version range stays external and is installed from
  // npm; only the workspace packages are inlined.
  packages: "external",
  external: ["@modelcontextprotocol/sdk", "zod"],
  banner: { js: "#!/usr/bin/env node" },
  logLevel: "info",
});

// npm preserves the executable bit from the tarball, and `bin` without it is a
// "permission denied" the first time anybody runs `npx notch-metrics-mcp`.
await chmod(outfile, 0o755);
