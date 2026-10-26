import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import matter from "gray-matter";
import { Marked } from "marked";
import { highlightText } from "rangi";
import { githubDark } from "rangi/themes";
import { z } from "zod";

/**
 * The markdown pipeline, shared by every collection of `.md` files.
 *
 * Extracted from `src/lib/blog.ts` when the content library arrived: two
 * collections parsing frontmatter with two copies of the same renderer is how
 * one of them quietly stops emitting heading anchors. The blog and the
 * library differ only in their directory and their frontmatter schema.
 *
 * Every consumer of this module is a statically rendered route — the entry
 * pages, the indexes, the sitemap, `/llms.txt`. That matters: `node:fs` does
 * not exist on the Worker this site deploys to, so a route that reads an
 * entry at request time would build fine and then 500 in production. If you
 * add a route that calls anything here, give it `export const dynamic =
 * "force-static"` so the read happens during `next build`.
 */

/** The byline when an entry does not name one. */
export const DEFAULT_AUTHOR = "Notch Metrics";

/**
 * `YYYY-MM-DD`, from either a string or a `Date`.
 *
 * YAML types a bare `2026-09-22` as a timestamp, so gray-matter hands us a
 * `Date` for an unquoted date and a string for a quoted one. Accepting both
 * is better than a rule that every date must be quoted — that rule is
 * invisible in the file that breaks it.
 */
export const IsoDate = z
  .union([z.string(), z.date()])
  .transform((value) => (value instanceof Date ? value.toISOString().slice(0, 10) : value.trim()))
  .refine((value) => /^\d{4}-\d{2}-\d{2}$/.test(value), "expected YYYY-MM-DD");

/**
 * An FAQ, required on every entry and never shorter than three.
 *
 * Non-optional on purpose. "Remember to add an FAQ" as a convention is
 * forgotten on the next article; as a schema field it is a build failure the
 * moment a file is added without one, which is the only version that holds
 * across sixty-odd files.
 */
export const FaqSchema = z
  .array(z.object({ question: z.string().min(1), answer: z.string().min(1) }))
  .min(3, "every entry needs at least three FAQ entries");

/** The frontmatter every collection shares. */
export const BaseFrontmatter = z.object({
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
  faq: FaqSchema,
  /** Kept out of the index, the sitemap and `/llms.txt`, and noindexed. */
  draft: z.boolean().default(false),
});

export type BaseEntry = z.infer<typeof BaseFrontmatter> & {
  slug: string;
  /** The raw markdown body, frontmatter stripped. Served to LLM crawlers. */
  markdown: string;
  /** The rendered body. */
  html: string;
  readingMinutes: number;
  /** `## ` headings, for the in-page table of contents. */
  headings: { id: string; text: string }[];
};

/**
 * The five characters that change meaning inside markup.
 *
 * `marked` escapes code for us on the path it owns, but the highlighter
 * returns markup, so the fallback branches have to escape their own.
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function slugify(text: string): string {
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
 * per-document, so the singleton would accumulate one entry's headings into
 * the next one's table of contents.
 */
export function renderMarkdown(markdown: string): {
  html: string;
  headings: { id: string; text: string }[];
} {
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
        // people copy out of a long entry.
        return `<h${depth} id="${id}"><a href="#${id}">${inner}</a></h${depth}>\n`;
      },
      /**
       * Syntax highlighting, at build time.
       *
       * `highlightText` rather than `codeToHtml`: the latter emits its own
       * `<div>` carrying a background, a radius, a font and a margin as
       * inline styles, which would override `.prose pre` and give the docs
       * two different code block shapes depending on whether a fence named
       * its language. This returns the tokens alone, so the site keeps its
       * own chrome and gains only the colours.
       *
       * A dark theme because `.prose pre` is `--color-ink` on a paper page,
       * and no line numbers: they arrive as a `<div>` gutter inside the
       * `<code>`, which is a second column the docs' short fences do not
       * want and which copies along with the code.
       *
       * An unknown or absent language falls through to escaped plain text.
       * A fence saying ```mermaid should render as code, not throw a build.
       */
      code({ text, lang }) {
        const language = (lang ?? "").trim().split(/\s+/)[0];
        let body: string;
        try {
          body = language
            ? highlightText(text, { lang: language, theme: githubDark, lineNumbers: false })
            : escapeHtml(text);
        } catch {
          body = escapeHtml(text);
        }
        const attribute = language ? ` data-lang="${escapeHtml(language)}"` : "";
        return `<pre${attribute}><code>${body}</code></pre>\n`;
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
  // already been through review. Raw HTML in an entry is therefore allowed —
  // if entries ever arrive from a CMS or a form, this needs a sanitiser.
  const html = md.parse(markdown, { async: false });
  return { html, headings };
}

/**
 * Every `.md` file in one directory, parsed and validated, newest first.
 *
 * Drafts stay visible under `next dev` so an entry can be reviewed at its
 * real URL before it is published.
 */
export function readCollection<S extends z.ZodType<Record<string, unknown>>>(
  dir: string,
  schema: S,
): (BaseEntry & z.infer<S>)[] {
  const root = join(process.cwd(), "content", dir);

  let files: string[];
  try {
    files = readdirSync(root).filter((file) => file.endsWith(".md"));
  } catch {
    // No content directory yet. An empty collection, not a build failure.
    return [];
  }

  const includeDrafts = process.env.NODE_ENV === "development";

  return files
    .map((file) => {
      const slug = file.replace(/\.md$/, "");
      const { data, content } = matter(readFileSync(join(root, file), "utf8"));
      const parsed = schema.safeParse(data);

      if (!parsed.success) {
        const issues = parsed.error.issues.map(
          (issue) => `  ${issue.path.join(".") || "(root)"}: ${issue.message}`,
        );
        // Thrown, not skipped. An entry with broken frontmatter silently
        // vanishing from the index is how you ship a 404 to the link you
        // just announced.
        throw new Error(`content/${dir}/${file} has invalid frontmatter:\n${issues.join("\n")}`);
      }

      const body = content.trim();
      const { html, headings } = renderMarkdown(body);
      const words = body.split(/\s+/).filter(Boolean).length;

      return {
        slug,
        ...parsed.data,
        markdown: body,
        html,
        headings,
        readingMinutes: Math.max(1, Math.round(words / 225)),
      } as BaseEntry & z.infer<S>;
    })
    .filter((entry) => includeDrafts || !entry.draft)
    .sort((a, b) => b.date.localeCompare(a.date));
}

/** Every tag in use, most-used first, ties broken alphabetically. */
export function tagsOf(entries: { tags: string[] }[]): { tag: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const entry of entries) {
    for (const tag of entry.tags) counts.set(tag, (counts.get(tag) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([tag, count]) => ({ tag, count }))
    .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag));
}

/** The date a crawler should treat as an entry's last change. */
export function lastModified(entry: { date: string; updated?: string }): string {
  return entry.updated ?? entry.date;
}

export function formatDate(iso: string): string {
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}
