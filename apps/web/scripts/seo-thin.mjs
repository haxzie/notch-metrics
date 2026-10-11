#!/usr/bin/env node
// Reports which generated pages carry too little of their own text.
//
// The `/sources` tree is generated from the provider manifests, and the
// failure mode of a set like that is seventy-seven pages reading as one page
// with the nouns swapped. This measures the thing that matters: not how long
// a page is, but how much of it is not also on the other pages.
//
// Method. Take the `<main>` of every built page, split it into sentences, and
// count how many pages each sentence appears on. A sentence on more than a
// quarter of them is chrome, a shared call to action or a generated phrase
// that varies in nothing but a name. What is left is the page's own text.
//
// It reports and exits 0. It must never fail the build: the whole point of
// generating these pages is that adding a metric to a manifest needs no edit
// in this app, and a check that breaks CI on a new metric would undo that.
// Read the list, write a sidecar in `content/sources` or
// `content/source-metrics` for whatever it names, and rebuild.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(process.cwd(), ".next", "server", "app");
const FLOOR = Number(process.env.SEO_THIN_FLOOR ?? 250);
// A sentence on more than this share of pages is boilerplate, not content.
const SHARED_AT = 0.25;

function htmlFiles(dir) {
  let out = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) out = out.concat(htmlFiles(path));
    else if (name.endsWith(".html")) out.push(path);
  }
  return out;
}

function mainText(html) {
  const main = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i)?.[1] ?? "";
  return main
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
}

function sentences(text) {
  return text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 12);
}

let files;
try {
  files = htmlFiles(ROOT).filter((f) => relative(ROOT, f).startsWith("sources"));
} catch {
  console.error("No build found. Run `pnpm --filter @notch/web build` first.");
  process.exit(0);
}

if (files.length === 0) {
  console.log("No generated /sources pages in the build.");
  process.exit(0);
}

const parsed = files.map((file) => {
  const url =
    "/" +
    relative(ROOT, file)
      .replace(/\.html$/, "")
      .replace(/\\/g, "/");
  return { url, sentences: sentences(mainText(readFileSync(file, "utf8"))) };
});

const seen = new Map();
for (const page of parsed) {
  for (const sentence of new Set(page.sentences)) {
    seen.set(sentence, (seen.get(sentence) ?? 0) + 1);
  }
}

const shared = Math.max(2, Math.ceil(parsed.length * SHARED_AT));

const scored = parsed
  .map((page) => {
    const own = page.sentences.filter((sentence) => (seen.get(sentence) ?? 0) < shared);
    return { url: page.url, words: own.join(" ").split(/\s+/).filter(Boolean).length };
  })
  .sort((a, b) => a.words - b.words);

const thin = scored.filter((page) => page.words < FLOOR);

console.log(`${parsed.length} generated pages, floor ${FLOOR} unique words.`);
console.log(`A sentence on ${shared} or more of them is treated as shared and does not count.\n`);

for (const page of scored.slice(0, 10)) {
  console.log(`  ${String(page.words).padStart(4)}  ${page.url}`);
}

console.log(
  `\n${thin.length} ${thin.length === 1 ? "page is" : "pages are"} under the floor.` +
    (thin.length > 0
      ? " Give each one a sidecar in content/sources or content/source-metrics."
      : ""),
);
