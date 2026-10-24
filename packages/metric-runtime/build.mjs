/**
 * Bundles the runner into one `.mjs` the Mac app ships and Node executes.
 *
 * This used to be `bun build --compile`, which produced a **61 MB** Mach-O
 * against a 16 MB app — the whole Bun runtime, since our own code is 112
 * modules that bundle in milliseconds. `--minify` made no difference for the
 * same reason. Paying 4.8× the download so that a feature most users never
 * touch needs no Node was the wrong trade.
 *
 * So the runtime is the user's. Anyone authoring a metric with an agent has a
 * dev environment; that is the audience, and it is the only audience that can
 * write one. What that costs is covered in `PluginRunner`: a GUI app does not
 * inherit a shell `PATH`, so finding their Node is real work.
 *
 * `zod` is inlined rather than left external. The app ships this file alone,
 * with no `node_modules` beside it, so an import that survives bundling is a
 * module resolution error at the first run rather than a build failure here.
 */
import { build } from "esbuild";

await build({
  entryPoints: ["src/cli.ts"],
  outfile: "dist/runner.mjs",
  bundle: true,
  format: "esm",
  platform: "node",
  // The floor the app checks for. Chosen for `node:test`-era stability rather
  // than anything exotic: the runner uses no syntax newer than this.
  target: "node20",
  // Nothing external. See above — there is no node_modules next to the
  // shipped file, so everything has to be in it.
  //
  // No `banner` with a shebang: `src/cli.ts` already starts with one and
  // esbuild keeps it. Adding a second put it on line 2, where it is no longer
  // a shebang but a syntax error — `#` is not valid JavaScript anywhere else.
  logLevel: "info",
});
