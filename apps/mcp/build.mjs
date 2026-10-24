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
  // Only the real npm dependencies stay external. Everything else — which
  // means the `@notch/*` workspace packages — is inlined, because they are
  // `workspace:*` and resolve to nothing on a machine that has never heard of
  // this monorepo.
  //
  // This used to also set `packages: "external"`, whose comment claimed the
  // workspace packages were inlined. They were not: that option marks *every*
  // bare import external and the `external` array adds to it rather than
  // narrowing it, so `@notch/schemas` and `@notch/metric-runtime` survived
  // into the bundle as imports. The published server would have failed on its
  // first run with "Cannot find module". It went unnoticed because nothing
  // was ever published.
  external: ["@modelcontextprotocol/sdk", "zod"],
  banner: { js: "#!/usr/bin/env node" },
  logLevel: "info",
});

// npm preserves the executable bit from the tarball, and `bin` without it is a
// "permission denied" the first time anybody runs `npx @notchmetrics/mcp`.
await chmod(outfile, 0o755);
