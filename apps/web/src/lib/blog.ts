import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import matter from "gray-matter";
import { Marked } from "marked";
import { z } from "zod";

/**
 * The blog, read from `content/blog/*.md` at build time.
 *
 * Every consumer of this module is a statically rendered route — the post
 * pages, the index, the sitemap, `/llms.txt`. That matters: `node:fs` does
 * not exist on the Worker this site deploys to, so a route that reads a post
 * at request time would build fine and then 500 in production. If you add a
 * route that calls anything here, give it `export const dynamic =
 * "force-static"` so the read happens during `next build`.
 */
const CONTENT_DIR = join(process.cwd(), "content", "blog");

/** The byline when a post does not name one. */
const DEFAULT_AUTHOR = "Notch Metrics";

/**
 * `YYYY-MM-DD`, from either a string or a `Date`.
 *
 * YAML types a bare `2026-09-22` as a timestamp, so gray-matter hands us a
 * `Date` for an unquoted date and a string for a quoted one. Accepting both
 * is better than a rule that every date must be quoted — that rule is
 * invisible in the file that breaks it.
 */
const IsoDate = z
  .union([z.string(), z.date()])
  .transform((value) => (value instanceof Date ? value.toISOString().slice(0, 10) : value.trim()))
  .refine((value) => /^\d{4}-\d{2}-\d{2}$/.test(value), "expected YYYY-MM-DD");

const Frontmatter = z.object({
  title: z.string().min(1),
  /**
   * Required, not derived from the body. This is the `<meta name="description">`
   * and the search snippet; an auto-cut first paragraph produces the kind of
   * truncated description that costs clicks.
   *
   * Capped at 160 characters because that is roughly where Google stops
   * rendering one. A longer description is not an error anywhere downstream,
   * which is exactly why the build has to be the thing that catches it.
   */
  description: z.string().min(1).max(160),
  /** Publication date, `YYYY-MM-DD`. */
  date: IsoDate,
  /** Set only when the text has materially changed since publication. */
  updated: IsoDate.optional(),
  author: z.string().min(1).default(DEFAULT_AUTHOR),
  tags: z.array(z.string().min(1)).default([]),
  /** Kept out of the index, the sitemap and `/llms.txt`, and noindexed. */
  draft: z.boolean().default(false),
});

export type Post = {
  slug: string;
  title: string;
  description: string;
  date: string;
  updated?: string;
  author: string;
  tags: string[];
  draft: boolean;
  /** The raw markdown body, frontmatter stripped. Served to LLM crawlers. */
  markdown: string;
  /** The rendered body. */
  html: string;
  readingMinutes: number;
  /** `## ` headings, for the in-page table of contents. */
  headings: { id: string; text: string }[];
};

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

/**
 * A `marked` instance per render, carrying our renderer overrides.
 *
 * A `new Marked()` rather than the module-level `marked.use()` singleton:
 * `use()` mutates shared state, and the heading collector below is
 * per-document, so the singleton would accumulate one post's headings into
 * the next one's table of contents.
 */
function render(markdown: string): { html: string; headings: { id: string; text: string }[] } {
  const headings: { id: string; text: string }[] = [];
  const seen = new Map<string, number>();

  const md = new Marked({ gfm: true });
  md.use({
    renderer: {
      heading({ tokens, depth, text }) {
        const base = slugify(text) || `section-${headings.length + 1}`;
        // Two headings with the same words would otherwise share an id, and
        // every link to the second one would scroll to the first.
        const count = seen.get(base) ?? 0;
        seen.set(base, count + 1);
        const id = count === 0 ? base : `${base}-${count + 1}`;

        if (depth === 2) headings.push({ id, text });

        const inner = this.parser.parseInline(tokens);
        // The anchor makes the heading itself the permalink, which is what
        // people copy out of a long post.
        return `<h${depth} id="${id}"><a href="#${id}">${inner}</a></h${depth}>\n`;
      },
      link({ href, title, tokens }) {
        const inner = this.parser.parseInline(tokens);
        const attrs = title ? ` title="${title}"` : "";
        const external = /^https?:\/\//.test(href) && !href.startsWith("https://notchmetrics.com");
        const rel = external ? ' target="_blank" rel="noopener noreferrer"' : "";
        return `<a href="${href}"${attrs}${rel}>${inner}</a>`;
      },
    },
  });

  // Not sanitised, and that is a decision rather than an oversight: the only
  // source of this markdown is a file committed to this repository, which has
  // already been through review. Raw HTML in a post is therefore allowed —
  // if posts ever arrive from a CMS or a form, this needs a sanitiser.
  const html = md.parse(markdown, { async: false });
  return { html, headings };
}

function parse(slug: string, raw: string): Post {
  const { data, content } = matter(raw);
  const parsed = Frontmatter.safeParse(data);
  if (!parsed.success) {
    const issues = parsed.error.issues.map(
      (i) => `  ${i.path.join(".") || "(root)"}: ${i.message}`,
    );
    // Thrown, not skipped. A post with broken frontmatter silently vanishing
    // from the index is how you ship a 404 to the link you just announced.
    throw new Error(`content/blog/${slug}.md has invalid frontmatter:\n${issues.join("\n")}`);
  }

  const body = content.trim();
  const { html, headings } = render(body);
  const words = body.split(/\s+/).filter(Boolean).length;

  return {
    slug,
    ...parsed.data,
    markdown: body,
    html,
    headings,
    readingMinutes: Math.max(1, Math.round(words / 225)),
  };
}

/**
 * Every post, newest first, drafts excluded in production.
 *
 * Drafts stay visible under `next dev` so a post can be reviewed at its real
 * URL before it is published.
 */
export function allPosts(): Post[] {
  let files: string[];
  try {
    files = readdirSync(CONTENT_DIR).filter((f) => f.endsWith(".md"));
  } catch {
    // No content directory yet. An empty blog, not a build failure.
    return [];
  }

  const includeDrafts = process.env.NODE_ENV === "development";

  return files
    .map((file) => parse(file.replace(/\.md$/, ""), readFileSync(join(CONTENT_DIR, file), "utf8")))
    .filter((post) => includeDrafts || !post.draft)
    .sort((a, b) => b.date.localeCompare(a.date));
}

export function postBySlug(slug: string): Post | undefined {
  return allPosts().find((post) => post.slug === slug);
}

/**
 * Every tag in use, most-used first, ties broken alphabetically.
 *
 * The count is returned but not rendered — it is the sort key, so the index
 * leads with the subjects the blog actually covers rather than with whichever
 * tag happens to sort first.
 */
export function allTags(posts: Post[] = allPosts()): { tag: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const post of posts) {
    for (const tag of post.tags) counts.set(tag, (counts.get(tag) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([tag, count]) => ({ tag, count }))
    .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag));
}

/** The date a crawler should treat as the post's last change. */
export function lastModified(post: Post): string {
  return post.updated ?? post.date;
}

export function formatDate(iso: string): string {
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}
