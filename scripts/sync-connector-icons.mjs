#!/usr/bin/env node
// Vendors each connector's brand mark from simple-icons into three places:
// the shared asset directory, the website's public dir, and the Mac asset
// catalogue.
//
// Committed rather than fetched at runtime. An icon that arrives over the
// network means the Integrations pane is a column of grey boxes on a bad
// connection, and the whole point of the pane is recognising a logo.
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as simpleIcons from "simple-icons";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// Our connector id → the brand's title in simple-icons. Matched on title
// rather than on simple-icons' own slug because the slug is derived from the
// title and has changed under us before.
//
// A connector absent from this map has no vendored mark and falls back to its
// SF Symbol on the Mac and to a lettermark on the web. That is deliberate:
// an approximated logo looks like a bug, a lettermark looks like a choice.
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
};

// No mark in simple-icons as of 16.x. Drop an official SVG into
// packages/ui/assets/connectors/<id>.svg and add the id here to stop the
// script overwriting it.
const UNVENDORED = ["polar", "amplitude", "ahrefs", "apollo"];

const icons = Object.values(simpleIcons).filter((icon) => icon && icon.title && icon.path);

function markFor(title) {
  const icon = icons.find((candidate) => candidate.title.toLowerCase() === title.toLowerCase());
  if (!icon) throw new Error(`simple-icons has no "${title}" — check the title, it may have moved`);
  return icon;
}

/**
 * White, not the brand colour: the glyph sits on a tile filled with the brand
 * colour, so a mark carrying its own near-black fill (PostHog, Apple) would
 * otherwise disappear.
 */
function svgFor(icon) {
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="${icon.title}">`,
    `<title>${icon.title}</title>`,
    `<path fill="#FFFFFF" d="${icon.path}"/>`,
    `</svg>`,
    ``,
  ].join("");
}

const SHARED = join(ROOT, "packages/ui/assets/connectors");
const WEB = join(ROOT, "apps/web/public/connectors");
const XCASSETS = join(ROOT, "apps/mac/App/Assets.xcassets/Connectors");

mkdirSync(SHARED, { recursive: true });
mkdirSync(WEB, { recursive: true });
mkdirSync(XCASSETS, { recursive: true });

// An asset catalogue folder needs its own Contents.json or xcodegen leaves it
// out of the build and every lookup silently returns nil.
writeFileSync(
  join(XCASSETS, "Contents.json"),
  JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2) + "\n",
);

const written = [];
for (const [id, title] of Object.entries(BRANDS)) {
  const icon = markFor(title);
  const svg = svgFor(icon);

  writeFileSync(join(SHARED, `${id}.svg`), svg);
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
        // blurry smear on every Retina display. The second keeps the mark
        // white instead of letting SwiftUI tint it as a template.
        properties: {
          "preserves-vector-representation": true,
          "template-rendering-intent": "original",
        },
      },
      null,
      2,
    ) + "\n",
  );

  written.push(id);
}

// Stale marks left behind after a connector is renamed or dropped would keep
// shipping in the app bundle.
for (const entry of readdirSync(XCASSETS)) {
  if (!entry.endsWith(".imageset")) continue;
  const id = entry.replace(/^connector-/, "").replace(/\.imageset$/, "");
  if (!written.includes(id)) rmSync(join(XCASSETS, entry), { recursive: true, force: true });
}

console.log(`${written.length} connector marks vendored`);
console.log(`${UNVENDORED.length} without one: ${UNVENDORED.join(", ")}`);
