import { z } from "zod";
import { type BaseEntry, readCollection } from "@/lib/collection";

export { formatDate, lastModified } from "@/lib/collection";

/**
 * The documentation, read from `content/docs/*.md` at build time.
 *
 * A third collection beside the blog and the library, and separate from both
 * for the reason they are separate from each other: these are read in order
 * by somebody building something, where a post is read once and a library
 * entry is arrived at from a search. Ordering is the whole difference, which
 * is why `section` and `order` are required here and nowhere else.
 *
 * Deliberately *not* `BaseFrontmatter`. A docs page has no author byline, no
 * tags and no reading time, and the FAQ that every post must carry would be
 * three invented questions on a reference page. What it keeps is `title`,
 * `description` and `date`, because the sitemap and the meta description
 * need all three.
 */
const Frontmatter = z.object({
  title: z.string().min(1),
  /** The `<meta name="description">`, capped where Google stops rendering. */
  description: z.string().min(1).max(160),
  date: z
    .union([z.string(), z.date()])
    .transform((value) => (value instanceof Date ? value.toISOString().slice(0, 10) : value.trim()))
    .refine((value) => /^\d{4}-\d{2}-\d{2}$/.test(value), "expected YYYY-MM-DD"),
  updated: z
    .union([z.string(), z.date()])
    .transform((value) => (value instanceof Date ? value.toISOString().slice(0, 10) : value.trim()))
    .refine((value) => /^\d{4}-\d{2}-\d{2}$/.test(value), "expected YYYY-MM-DD")
    .optional(),
  /** Which sidebar group this sits in. */
  section: z.enum(["start", "widgets", "apps"]),
  /**
   * Position inside the section, ascending.
   *
   * Explicit, not alphabetical and not by date. Documentation is read top to
   * bottom the first time, and "what a widget is" has to come before "the
   * widget types" however the files happen to sort.
   */
  order: z.number().int().min(0),
  /**
   * A one-line summary for the index cards and `/llms.txt`.
   *
   * Separate from `description`, which is written for a search result. This
   * one is written for somebody already on the page deciding where to click.
   */
  summary: z.string().min(1).max(120),
  /** Unused by docs, present so the shared entry type stays honest. */
  faq: z.array(z.object({ question: z.string(), answer: z.string() })).default([]),
  tags: z.array(z.string()).default([]),
  author: z.string().default("Notch Metrics"),
  draft: z.boolean().default(false),
});

export type DocPage = BaseEntry & z.infer<typeof Frontmatter>;
export type DocSection = DocPage["section"];

export const SECTION_LABELS: Record<DocSection, string> = {
  start: "Getting started",
  widgets: "Widgets",
  apps: "Custom apps",
};

/** The order the sidebar shows the groups in. */
export const SECTION_ORDER: DocSection[] = ["start", "widgets", "apps"];

export function allDocs(): DocPage[] {
  // `readCollection` sorts newest first, which is meaningless here. Every
  // consumer wants reading order, so it is applied once, at the source.
  return readCollection("docs", Frontmatter).sort(
    (a, b) =>
      SECTION_ORDER.indexOf(a.section) - SECTION_ORDER.indexOf(b.section) ||
      a.order - b.order ||
      a.title.localeCompare(b.title),
  );
}

export function docBySlug(slug: string): DocPage | undefined {
  return allDocs().find((doc) => doc.slug === slug);
}

export function docGroups(
  docs: DocPage[] = allDocs(),
): { section: DocSection; label: string; docs: DocPage[] }[] {
  return SECTION_ORDER.map((section) => ({
    section,
    label: SECTION_LABELS[section],
    docs: docs.filter((doc) => doc.section === section),
  })).filter((group) => group.docs.length > 0);
}

/**
 * The sidebar's groups, with the introduction standing in for `/docs`.
 *
 * The index route *is* the introduction, so it has no markdown file and
 * cannot come out of the collection. Injected here rather than special cased
 * in the sidebar component, so the rail and the index cards agree about what
 * the first page is.
 */
export function sidebarGroups(): { label: string; docs: { slug: string; title: string }[] }[] {
  return docGroups().map((group) => ({
    label: group.label,
    docs: [
      ...(group.section === SECTION_ORDER[0] ? [{ slug: "", title: "Introduction" }] : []),
      ...group.docs.map((doc) => ({ slug: doc.slug, title: doc.title })),
    ],
  }));
}

/**
 * The page before and after this one, in reading order.
 *
 * Across section boundaries on purpose: the sections are one sequence, and a
 * reader who finishes the last page of "Widgets" wants the first page of
 * "Build your own" and not a dead end.
 */
export function docNeighbours(slug: string): { previous?: DocPage; next?: DocPage } {
  const docs = allDocs();
  const index = docs.findIndex((doc) => doc.slug === slug);
  if (index === -1) return {};
  return { previous: docs[index - 1], next: docs[index + 1] };
}
