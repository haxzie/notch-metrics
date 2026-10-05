#!/usr/bin/env node
/**
 * Slices one version's section out of `apps/mac/CHANGELOG.md`.
 *
 * Better than `gh release create --generate-notes` now that changesets owns
 * the record of what changed: generated notes list every commit, including the
 * ones that say "fix types".
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const version = process.argv[2];

if (!version) {
  console.error("usage: release-notes.mjs <version>");
  process.exit(2);
}

const fallback = `Notch Metrics ${version}.`;

let changelog;
try {
  changelog = readFileSync(join(root, "apps", "mac", "CHANGELOG.md"), "utf8");
} catch {
  // No changelog yet is the normal state for the first release, and an empty
  // release body is better than a failed release.
  console.log(fallback);
  process.exit(0);
}

const lines = changelog.split("\n");
const start = lines.findIndex((line) => line.trim() === `## ${version}`);

if (start === -1) {
  console.log(fallback);
  process.exit(0);
}

const rest = lines.slice(start + 1);
const end = rest.findIndex((line) => /^## /.test(line));
const body = (end === -1 ? rest : rest.slice(0, end)).join("\n").trim();

console.log(body || fallback);
