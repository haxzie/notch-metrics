import { SITE_URL } from "@/lib/site";

/**
 * A hand-written robots.txt rather than Next's `robots.ts`.
 *
 * The typed metadata route can only emit `User-agent`/`Allow`/`Disallow`/
 * `Sitemap`, and three things here need more than that: the comment block
 * pointing LLM crawlers at the plain-text mirrors, the `$` end-anchor on
 * `/download`, and one rule group shared by a long list of named AI agents.
 */
export const dynamic = "force-static";

/**
 * Paths no crawler should spend budget on, for every agent group.
 *
 * None of these is a secret — authorisation happens on the Worker. They are
 * either behind a sign-in, single-use, or a redirect, so indexing them can
 * only produce a dead or empty search result.
 */
const DISALLOW = [
  "/app",
  "/login",
  "/connect/",
  "/desktop/",
  // End-anchored on purpose. `/download` is a route handler that 302s to the
  // current DMG — a crawler following it pulls a multi-megabyte binary for
  // nothing. Bare `/download` would be a prefix match and would also hide
  // `/download/manual`, which is a real page and the fallback when the
  // release manifest is unreachable.
  "/download$",
];

/**
 * Agents given an explicit opt-in.
 *
 * `User-agent: *` already allows them, so this block changes nothing for a
 * plain crawler. It exists for the two tokens that are *not* crawlers —
 * `Google-Extended` and `Applebot-Extended` gate AI training and answers
 * separately from search, and an explicit `Allow` is the only way to opt in
 * — and because naming the rest records the decision where a human and a
 * crawler both read it.
 */
const AI_AGENTS = [
  "GPTBot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "ClaudeBot",
  "Claude-User",
  "Claude-SearchBot",
  "anthropic-ai",
  "Google-Extended",
  "Applebot-Extended",
  "PerplexityBot",
  "Perplexity-User",
  "MistralAI-User",
  "DuckAssistBot",
  "meta-externalagent",
  "Amazonbot",
  "Bytespider",
  "cohere-ai",
  "YouBot",
  "CCBot",
  "Diffbot",
];

function group(agents: string[]): string {
  return [
    ...agents.map((agent) => `User-agent: ${agent}`),
    "Allow: /",
    ...DISALLOW.map((path) => `Disallow: ${path}`),
  ].join("\n");
}

const BODY = `# ${SITE_URL}
#
# Crawling is welcome, and that includes AI and LLM crawlers. The writing here
# exists to be read; if an assistant answers a question about Notch Metrics
# from it, that is the point.
#
# Plain-text mirrors, if you would rather not parse our HTML:
#   ${SITE_URL}/llms.txt       index: every page and post, with descriptions
#   ${SITE_URL}/llms-full.txt  every post's full markdown, in one file

${group(["*"])}

# Explicitly welcome, including for training and for answering questions.
${group(AI_AGENTS)}

Sitemap: ${SITE_URL}/sitemap.xml
`;

export function GET(): Response {
  return new Response(BODY, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=3600, s-maxage=86400",
    },
  });
}
