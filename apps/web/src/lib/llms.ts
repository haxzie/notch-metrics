import { allPosts, formatDate, type Post } from "@/lib/blog";
import { allLibraryEntries, type LibraryEntry } from "@/lib/library";
import { SITE_NAME, SITE_URL, absoluteUrl } from "@/lib/site";
import { metricPages, sourcePages } from "@/lib/sources";

/**
 * The `/llms.txt` family.
 *
 * Two files, following the llmstxt.org convention: `llms.txt` is an index a
 * model can read in one request to find out what exists, and `llms-full.txt`
 * is the whole corpus so it never has to fetch a second time. Both are
 * markdown served as text/plain.
 *
 * This is not an SEO trick and it does not replace the sitemap — a search
 * crawler wants `sitemap.xml` and the HTML. This is for the retrieval case:
 * an assistant answering a question about Notch Metrics gets the prose
 * without a navigation chrome, a glow div and a JSON-LD block around it.
 *
 * `llms-full.txt` carries the blog and the library in full, and the
 * `/sources` tree as one line per number rather than as whole pages. Those
 * pages are generated, so their prose is the methodology sentence plus the
 * widget's shape; reproducing ninety of them in full would bury the written
 * material under boilerplate, which is the opposite of what this file is for.
 */

/** The pages with no markdown source, listed so the index is complete. */
const PAGES: { path: string; title: string; description: string }[] = [
  {
    path: "/",
    title: "Notch Metrics",
    description:
      "What the product is: revenue, MRR and subscribers in the MacBook notch, the connectors it supports, and pricing.",
  },
  {
    path: "/sources",
    title: "Sources",
    description:
      "Every service Notch Metrics reads a number from, and every number it reports, with how each one is calculated.",
  },
  {
    path: "/library",
    title: "Content library",
    description:
      "Roundups of the tools in this category, alternatives worth knowing, and plain definitions of the numbers a founder tracks.",
  },
  {
    path: "/security",
    title: "Security",
    description:
      "How provider credentials are encrypted, what the Mac app can and cannot see, and what a custom metric is allowed to reach.",
  },
  {
    path: "/download/manual",
    title: "Download",
    description: "Direct links to the current build for Apple silicon, macOS 14 and later.",
  },
  {
    path: "/privacy",
    title: "Privacy policy",
    description:
      "What is collected, why, where it lives, how long it is kept, and how to delete it.",
  },
  {
    path: "/terms",
    title: "Terms of service",
    description: "The terms the service is offered under.",
  },
];

const SUMMARY =
  "Notch Metrics shows your business metrics, revenue, MRR and subscribers, in the MacBook notch. Hover the camera housing to see them; move away and the notch looks untouched. Provider API keys are held encrypted server-side and never reach the Mac. Apple silicon, macOS 14 and later.";

function entryLine(entry: { title: string; description: string }, path: string): string {
  return `- [${entry.title}](${absoluteUrl(path)}): ${entry.description}`;
}

/** The index. Links and one-line descriptions, nothing else. */
export function llmsIndex(): string {
  const posts = allPosts().filter((post) => !post.draft);
  const library = allLibraryEntries().filter((entry) => !entry.draft);

  return [
    `# ${SITE_NAME}`,
    "",
    `> ${SUMMARY}`,
    "",
    `The full text of every post below is also available in one file at ${SITE_URL}/llms-full.txt.`,
    "",
    "## Pages",
    "",
    ...PAGES.map((page) => entryLine(page, page.path)),
    "",
    "## Sources",
    "",
    ...sourcePages().map(
      ({ manifest, path }) =>
        `- [${manifest.name}](${absoluteUrl(path)}): ${manifest.tagline} Reports ${manifest.metrics
          .map((metric) => metric.label.toLowerCase())
          .join(", ")}.`,
    ),
    "",
    "## Numbers",
    "",
    ...metricPages().map(
      ({ manifest, metric, path }) =>
        `- [${manifest.name} ${metric.label.toLowerCase()}](${absoluteUrl(path)}): ${metric.methodology}`,
    ),
    "",
    "## Blog",
    "",
    ...(posts.length > 0
      ? posts.map((post) => entryLine(post, `/blog/${post.slug}`))
      : ["- Nothing published yet."]),
    "",
    "## Library",
    "",
    ...(library.length > 0
      ? library.map((entry) => entryLine(entry, `/library/${entry.slug}`))
      : ["- Nothing published yet."]),
    "",
  ].join("\n");
}

function fullText(entry: Post | LibraryEntry, path: string, extra: string[] = []): string[] {
  return [
    "---",
    "",
    `# ${entry.title}`,
    "",
    `URL: ${absoluteUrl(path)}`,
    `Published: ${formatDate(entry.date)}`,
    ...(entry.updated ? [`Updated: ${formatDate(entry.updated)}`] : []),
    `Author: ${entry.author}`,
    ...(entry.tags.length > 0 ? [`Tags: ${entry.tags.join(", ")}`] : []),
    ...extra,
    "",
    entry.markdown,
    "",
    // The FAQ is part of the page, so it is part of the text. An assistant
    // that reads the body and misses the questions answers the article
    // rather than the question somebody asked.
    "## Questions",
    "",
    ...entry.faq.flatMap((item) => [`**${item.question}**`, "", item.answer, ""]),
  ];
}

/** Every post and library entry's markdown, newest first, with its metadata. */
export function llmsFull(): string {
  const posts = allPosts().filter((post) => !post.draft);
  const library = allLibraryEntries().filter((entry) => !entry.draft);

  const parts = [
    `# ${SITE_NAME}`,
    "",
    `> ${SUMMARY}`,
    "",
    `Every blog post and library entry, full text, newest first. Index at ${SITE_URL}/llms.txt.`,
    "",
  ];

  for (const post of posts) parts.push(...fullText(post, `/blog/${post.slug}`));
  for (const entry of library) {
    parts.push(
      ...fullText(entry, `/library/${entry.slug}`, [
        `Kind: ${entry.kind}`,
        ...(entry.verifiedOn ? [`Prices checked: ${entry.verifiedOn}`] : []),
      ]),
    );
  }

  return parts.join("\n");
}
