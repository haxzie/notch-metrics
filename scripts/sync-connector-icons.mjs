#!/usr/bin/env node
// Vendors each connector's brand mark into the places that render one: the
// website's public dir and the Mac asset catalogue.
//
// Two sources, in priority order:
//
//   1. `packages/ui/assets/connectors/overrides/<id>.svg` — a committed,
//      full-colour official mark. Wins, and renders at its own colours.
//   2. simple-icons — a monochrome path, rendered white on a tile of the
//      brand's colour.
//
// The override exists because simple-icons is monochrome by design, and for
// some brands that loses the logo. Its Google Search Console glyph is also
// simply the old one.
//
// Committed rather than fetched at runtime: a logo arriving over the network
// makes the Integrations pane a column of grey boxes on a bad connection, and
// recognising a logo is the whole job of that view.
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as simpleIcons from "simple-icons";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// Our connector id → the brand's title in simple-icons. Matched on title
// rather than on simple-icons' own slug because the slug is derived from the
// title and has changed under us before.
//
// A connector in neither this map nor `overrides/` has no mark and falls back
// to its SF Symbol on the Mac and to a lettermark on the web. That is
// deliberate: an approximated logo looks like a bug, a lettermark looks like
// a choice.
const BRANDS = {
  stripe: "Stripe",
  dodopayments: "Dodo Payments",
  lemonsqueezy: "Lemon Squeezy",
  paddle: "Paddle",
  posthog: "PostHog",
  plausible: "Plausible Analytics",
  mixpanel: "Mixpanel",
  "google-analytics": "Google Analytics",
  "google-search-console": "Google Search Console",
  "google-ads": "Google Ads",
  "meta-ads": "Meta",
  hubspot: "HubSpot",
  intercom: "Intercom",
  github: "GitHub",
};

const OVERRIDES = join(ROOT, "packages/ui/assets/connectors/overrides");
const WEB = join(ROOT, "apps/web/public/connectors");
const XCASSETS = join(ROOT, "apps/mac/App/Assets.xcassets/Connectors");

const icons = Object.values(simpleIcons).filter((icon) => icon && icon.title && icon.path);

function monochromeSvg(title) {
  const icon = icons.find((candidate) => candidate.title.toLowerCase() === title.toLowerCase());
  if (!icon) throw new Error(`simple-icons has no "${title}" — check the title, it may have moved`);
  // White, not the brand colour: these sit on a tile filled with the brand
  // colour, so a mark carrying its own near-black fill would disappear.
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="${icon.title}">` +
    `<title>${icon.title}</title><path fill="#FFFFFF" d="${icon.path}"/></svg>\n`
  );
}

mkdirSync(WEB, { recursive: true });
mkdirSync(XCASSETS, { recursive: true });

// An asset catalogue folder needs its own Contents.json or xcodegen leaves it
// out of the build and every lookup silently returns nil.
writeFileSync(
  join(XCASSETS, "Contents.json"),
  JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2) + "\n",
);

const fullColour = [];
const monochrome = [];

for (const id of new Set([...Object.keys(BRANDS), ...overrideIds()])) {
  const override = join(OVERRIDES, `${id}.svg`);
  let svg;

  if (existsSync(override)) {
    svg = readFileSync(override, "utf8");
    fullColour.push(id);
  } else {
    svg = monochromeSvg(BRANDS[id]);
    monochrome.push(id);
  }

  writeFileSync(join(WEB, `${id}.svg`), svg);

  // Namespaced: a connector id must not be able to collide with Logo or AppIcon.
  const imageset = join(XCASSETS, `connector-${id}.imageset`);
  mkdirSync(imageset, { recursive: true });
  writeFileSync(join(imageset, `${id}.svg`), svg);
  writeFileSync(
    join(imageset, "Contents.json"),
    JSON.stringify(
      {
        images: [{ filename: `${id}.svg`, idiom: "universal" }],
        info: { author: "xcode", version: 1 },
        // Without the first, macOS rasterises once at 1x and the tile is a
        // blurry smear on every Retina display. The second keeps the mark's
        // own colours instead of letting SwiftUI tint it as a template.
        properties: {
          "preserves-vector-representation": true,
          "template-rendering-intent": "original",
        },
      },
      null,
      2,
    ) + "\n",
  );
}

fullColour.sort();
monochrome.sort();
const shipped = [...fullColour, ...monochrome];

// Stale marks left behind after a connector is renamed or dropped would keep
// shipping in the app bundle.
for (const entry of readdirSync(XCASSETS)) {
  if (!entry.endsWith(".imageset")) continue;
  const id = entry.replace(/^connector-/, "").replace(/\.imageset$/, "");
  if (!shipped.includes(id)) rmSync(join(XCASSETS, entry), { recursive: true, force: true });
}
for (const entry of readdirSync(WEB)) {
  const id = entry.replace(/\.svg$/, "");
  if (!shipped.includes(id)) rmSync(join(WEB, entry), { force: true });
}

// Both apps need to know which treatment a mark takes, and neither can tell
// by looking at the file. Generated rather than hand-kept, so adding an
// override cannot leave one of them rendering it the wrong way.
writeFileSync(
  join(ROOT, "apps/web/src/lib/connector-marks.generated.ts"),
  `// Generated by scripts/sync-connector-icons.mjs. Do not edit.\n` +
    `export const FULL_COLOUR_MARKS: ReadonlySet<string> = new Set(${JSON.stringify(fullColour)});\n` +
    `export const MARKS: ReadonlySet<string> = new Set(${JSON.stringify(shipped)});\n`,
);

writeFileSync(
  join(ROOT, "apps/mac/Kit/Sources/NotchUI/ConnectorMarks.generated.swift"),
  `// Generated by scripts/sync-connector-icons.mjs. Do not edit.\n\n` +
    `public enum ConnectorMarks {\n` +
    `    /// Rendered at their own colours, on a near-white tile.\n` +
    `    public static let fullColour: Set<String> = [\n` +
    fullColour.map((id) => `        "${id}",`).join("\n") +
    `\n    ]\n}\n`,
);

function overrideIds() {
  if (!existsSync(OVERRIDES)) return [];
  return readdirSync(OVERRIDES)
    .filter((entry) => entry.endsWith(".svg"))
    .map((entry) => entry.replace(/\.svg$/, ""));
}

console.log(`${fullColour.length} full-colour: ${fullColour.join(", ")}`);
console.log(`${monochrome.length} monochrome:  ${monochrome.join(", ")}`);
