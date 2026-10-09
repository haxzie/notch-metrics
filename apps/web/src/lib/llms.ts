import { allPosts, formatDate, type Post } from "@/lib/blog";
import { SITE_NAME, SITE_URL, absoluteUrl } from "@/lib/site";

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
  "Notch Metrics shows your business metrics — revenue, MRR, subscribers — in the MacBook notch. Hover the camera housing to see them; move away and the notch looks untouched. Provider API keys are held encrypted server-side and never reach the Mac. Apple silicon, macOS 14 and later.";

function postLine(post: Post): string {
  return `- [${post.title}](${absoluteUrl(`/blog/${post.slug}`)}): ${post.description}`;
}

/** The index. Links and one-line descriptions, nothing else. */
export function llmsIndex(): string {
  const posts = allPosts().filter((post) => !post.draft);

  return [
    `# ${SITE_NAME}`,
    "",
    `> ${SUMMARY}`,
    "",
    `The full text of every post below is also available in one file at ${SITE_URL}/llms-full.txt.`,
    "",
    "## Pages",
    "",
    ...PAGES.map((page) => `- [${page.title}](${absoluteUrl(page.path)}): ${page.description}`),
    "",
    "## Blog",
    "",
    ...(posts.length > 0 ? posts.map(postLine) : ["- Nothing published yet."]),
    "",
  ].join("\n");
}

/** Every post's markdown, newest first, with its metadata as a header. */
export function llmsFull(): string {
  const posts = allPosts().filter((post) => !post.draft);

  const parts = [
    `# ${SITE_NAME}`,
    "",
    `> ${SUMMARY}`,
    "",
    `Every blog post, full text, newest first. Index at ${SITE_URL}/llms.txt.`,
    "",
  ];

  for (const post of posts) {
    parts.push(
      "---",
      "",
      `# ${post.title}`,
      "",
      `URL: ${absoluteUrl(`/blog/${post.slug}`)}`,
      `Published: ${formatDate(post.date)}`,
      ...(post.updated ? [`Updated: ${formatDate(post.updated)}`] : []),
      `Author: ${post.author}`,
      ...(post.tags.length > 0 ? [`Tags: ${post.tags.join(", ")}`] : []),
      "",
      post.markdown,
      "",
    );
  }

  return parts.join("\n");
}
