#!/usr/bin/env node
/**
 * The `prepare` hook. Seeds the gitignored env files from their committed
 * examples so a fresh clone — including a CI runner — runs with no setup.
 *
 * Never overwrites. The whole point is that it is safe to run on every install.
 */
import { copyFileSync, existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const pairs = [
  [".env.example", ".env"],
  ["apps/api/.dev.vars.example", "apps/api/.dev.vars"],
];

const created = [];
for (const [example, target] of pairs) {
  const from = join(root, example);
  const to = join(root, target);
  if (!existsSync(from) || existsSync(to)) continue;
  copyFileSync(from, to);
  created.push(target);
}

if (created.length === 0) process.exit(0);

console.log(`Created ${created.join(", ")} from the examples.`);

// Name what is still empty. "It runs but every request 500s" is a much worse
// first five minutes than a list of three variables to fill in.
const blanks = [];
for (const [, target] of pairs) {
  const path = join(root, target);
  if (!existsSync(path)) continue;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const match = /^([A-Z][A-Z0-9_]*)=\s*$/.exec(line.trim());
    if (match) blanks.push(`${target}: ${match[1]}`);
  }
}

if (blanks.length > 0) {
  console.log("\nStill to fill in:");
  for (const blank of blanks) console.log(`  ${blank}`);
  console.log("\nThe app runs without most of them; see the comments in each file.");
}
