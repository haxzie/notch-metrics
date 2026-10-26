#!/usr/bin/env node
// Renders the social card once, to `public/og.png`.
//
// A committed PNG rather than an `opengraph-image.tsx` route. The route was
// static too — Next drew it at build — but it still meant Satori, a font
// loader and the connector catalogue running inside every web build, and a
// card that changes only when somebody edits it has no business being
// recomputed on each deploy.
//
// Run after changing `src/lib/og-hero.tsx`, and commit the result.
//
// esbuild because the card is TSX and Node has no JSX. `next/og` and the
// catalogue stay external: the first is a prebuilt binary wrapper, and the
// second reads the real manifests, which is the point of looking the brand
// colours up rather than hard-coding them.
import { mkdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const require = createRequire(import.meta.url);

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BUNDLE = join(ROOT, ".next", "cache", "og-hero.mjs");
const OUT = join(ROOT, "public", "og.png");

mkdirSync(dirname(BUNDLE), { recursive: true });

// `next` publishes no `./og` entry in its export map, so plain Node ESM
// cannot import `next/og` however the bundle is placed — only webpack and
// turbopack resolve it, which is why the app itself can. Aliasing it into
// the bundle is worse: that drags in `react-server-dom-webpack` and two
// `.wasm` files esbuild has no loader for.
//
// So it is loaded as CJS through a shim, with the path built at run time so
// esbuild leaves the call alone.
const SHIM = join(ROOT, ".next", "cache", "og-next-shim.mjs");
const ogEntry = require.resolve("next/og.js");
writeFileSync(
  SHIM,
  [
    'import { createRequire } from "node:module";',
    "const load = createRequire(import.meta.url);",
    `const entry = ${JSON.stringify(ogEntry)};`,
    "export const { ImageResponse } = load(entry);",
    "",
  ].join("\n"),
);

await build({
  entryPoints: [join(ROOT, "src", "lib", "og-hero.tsx")],
  outfile: BUNDLE,
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node22",
  jsx: "automatic",
  external: ["@notch/integrations", "react", "react/jsx-runtime", "node:module"],
  alias: {
    // The one alias the card reaches for, and it is a single constant.
    // Resolved here rather than teaching esbuild the tsconfig paths.
    "@/lib/og": join(ROOT, "src", "lib", "og.tsx"),
    "@/lib/site": join(ROOT, "src", "lib", "site.ts"),
    "next/og": SHIM,
  },
  logLevel: "warning",
});

const { ogHero } = await import(BUNDLE);
const response = ogHero();
const bytes = Buffer.from(await response.arrayBuffer());

writeFileSync(OUT, bytes);
console.log(`Wrote ${OUT} (${(bytes.length / 1024).toFixed(0)} KB)`);
