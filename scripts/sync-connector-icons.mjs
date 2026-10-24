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
  revenuecat: "RevenueCat",
  shopify: "Shopify",
  posthog: "PostHog",
  plausible: "Plausible Analytics",
  mixpanel: "Mixpanel",
  "google-analytics": "Google Analytics",
  "google-search-console": "Google Search Console",
  youtube: "YouTube",
  github: "GitHub",
};

/**
 * Overrides whose artwork is drawn for a *dark* background, so they keep the
 * brand-coloured tile instead of the near-white one.
 *
 * Dodo Payments' mark is lime on black; on a white tile it is barely there.
 * Polar's mark is white — it is `currentColor` on their own site, black on
 * light and white on dark, and we take the dark half. PostHog's carries a
 * white glyph inside the hedgehog, which disappears entirely on a light tile.
 */
const BRAND_TILE = new Set(["dodopayments", "polar", "posthog", "openai", "anthropic"]);

/**
 * Overrides that *are* the tile: artwork already square, already filled to
 * its viewBox.
 *
 * They are drawn edge to edge and clipped to the tile's corner radius rather
 * than inset into it — the usual 54% inset would float a lime square inside a
 * second square and read as a sticker.
 */
const FULL_BLEED = new Set(["dodopayments"]);

/**
 * Light-background overrides that are a single dark colour, so they can be
 * drawn as a white silhouette on glass and lose nothing.
 *
 * Everything else drawn for light is multicolour — Analytics' two ambers,
 * Search Console's four Google colours — and silhouetting those is exactly
 * what turned the Analytics mark into a generic bar chart. They keep a
 * near-white tile and their own colours.
 */
const MONOCHROME = new Set(["github"]);

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

// Which marks sit on a near-white tile. Everything else keeps the brand
// colour behind a white glyph.
const lightTile = [];
const brandTile = [];
// Marks that carry their own colours, i.e. the committed overrides. Their
// tile is used exactly as the brand specifies it, with no luminance floor —
// the floor is there to keep a *white glyph* legible, and lifting Dodo
// Payments' black to grey just makes the tile look washed out next to the
// lime it was designed against.
const ownColour = [];
const fullBleed = [];
const monochrome = [];

for (const id of new Set([...Object.keys(BRANDS), ...overrideIds()])) {
  const override = join(OVERRIDES, `${id}.svg`);
  let svg;

  if (existsSync(override)) {
    svg = readFileSync(override, "utf8");
    ownColour.push(id);
    if (FULL_BLEED.has(id)) fullBleed.push(id);
    if (MONOCHROME.has(id)) monochrome.push(id);
    (BRAND_TILE.has(id) ? brandTile : lightTile).push(id);
  } else {
    svg = monochromeSvg(BRANDS[id]);
    brandTile.push(id);
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

lightTile.sort();
brandTile.sort();
ownColour.sort();
fullBleed.sort();
monochrome.sort();
const shipped = [...lightTile, ...brandTile].sort();

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
    `export const LIGHT_TILE_MARKS: ReadonlySet<string> = new Set(${JSON.stringify(lightTile)});\n` +
    `export const OWN_COLOUR_MARKS: ReadonlySet<string> = new Set(${JSON.stringify(ownColour)});\n` +
    `export const FULL_BLEED_MARKS: ReadonlySet<string> = new Set(${JSON.stringify(fullBleed)});\n` +
    `export const MONOCHROME_MARKS: ReadonlySet<string> = new Set(${JSON.stringify(monochrome)});\n` +
    `export const MARKS: ReadonlySet<string> = new Set(${JSON.stringify(shipped)});\n`,
);

writeFileSync(
  join(ROOT, "apps/mac/Kit/Sources/NotchUI/ConnectorMarks.generated.swift"),
  `// Generated by scripts/sync-connector-icons.mjs. Do not edit.\n\n` +
    `public enum ConnectorMarks {\n` +
    `    /// Marks drawn for a light background, so they need one.\n` +
    `    public static let lightTile: Set<String> = [\n` +
    lightTile.map((id) => `        "${id}",`).join("\n") +
    `\n    ]\n\n` +
    `    /// Marks with their own colours, whose tile is used exactly as the\n` +
    `    /// brand specifies it — no luminance floor.\n` +
    `    public static let ownColour: Set<String> = [\n` +
    ownColour.map((id) => `        "${id}",`).join("\n") +
    `\n    ]\n\n` +
    `    /// Marks that are the tile: drawn edge to edge and clipped to its\n` +
    `    /// corner radius, rather than inset into it.\n` +
    `    public static let fullBleed: Set<String> = [\n` +
    fullBleed.map((id) => `        "${id}",`).join("\n") +
    `\n    ]\n\n` +
    `    /// Light-background marks in a single dark colour, which can be drawn\n` +
    `    /// as a white silhouette on glass. A multicolour mark cannot.\n` +
    `    public static let monochrome: Set<String> = [\n` +
    monochrome.map((id) => `        "${id}",`).join("\n") +
    `\n    ]\n}\n`,
);

function overrideIds() {
  if (!existsSync(OVERRIDES)) return [];
  return readdirSync(OVERRIDES)
    .filter((entry) => entry.endsWith(".svg"))
    .map((entry) => entry.replace(/\.svg$/, ""));
}

console.log(`${lightTile.length} on a light tile: ${lightTile.join(", ")}`);
console.log(`${brandTile.length} on a brand tile: ${brandTile.join(", ")}`);
