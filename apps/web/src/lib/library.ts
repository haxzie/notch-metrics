import { z } from "zod";
import { BaseFrontmatter, type BaseEntry, readCollection } from "@/lib/collection";

export { formatDate, lastModified } from "@/lib/collection";

/**
 * The content library, read from `content/library/*.md` at build time.
 *
 * Separate from the blog because the two are read by different people. The
 * blog is how-tos someone follows; the library is the reference shelf —
 * roundups, alternatives, and definitions somebody arrives at from a search
 * and leaves again. Keeping them apart stops a glossary entry for "churn"
 * competing with the post that explains how to measure it.
 *
 * It is indexed and it is in the sitemap. The footer link is the primary
 * route in, and related posts link across, because a page reachable only from
 * a footer is a page nothing votes for.
 */
const Frontmatter = BaseFrontmatter.extend({
  /**
   * What kind of page this is. Drives the index grouping and the eyebrow.
   *
   * Required rather than defaulted: an entry that lands in the wrong group
   * looks like a bug in the index, and the author is the only one who knows
   * which group it belongs in.
   */
  kind: z.enum(["comparison", "alternatives", "glossary"]),
  /** The term being defined, for a glossary entry's structured data. */
  term: z.string().min(1).optional(),
  /** When the prices or facts in a comparison were last read off the source. */
  verifiedOn: z.string().optional(),
});

export type LibraryEntry = BaseEntry & z.infer<typeof Frontmatter>;
export type LibraryKind = LibraryEntry["kind"];

export const KIND_LABELS: Record<LibraryKind, string> = {
  comparison: "Comparisons",
  alternatives: "Alternatives",
  glossary: "Glossary",
};

/** The order the index shows the groups in. */
export const KIND_ORDER: LibraryKind[] = ["comparison", "alternatives", "glossary"];

export function allLibraryEntries(): LibraryEntry[] {
  return readCollection("library", Frontmatter);
}

export function libraryEntryBySlug(slug: string): LibraryEntry | undefined {
  return allLibraryEntries().find((entry) => entry.slug === slug);
}

export function libraryGroups(
  entries: LibraryEntry[] = allLibraryEntries(),
): { kind: LibraryKind; label: string; entries: LibraryEntry[] }[] {
  return KIND_ORDER.map((kind) => ({
    kind,
    label: KIND_LABELS[kind],
    // Alphabetical inside a group. These are looked up by name, not browsed
    // by date, which is the difference between this index and the blog's.
    entries: entries
      .filter((entry) => entry.kind === kind)
      .sort((a, b) => a.title.localeCompare(b.title)),
  })).filter((group) => group.entries.length > 0);
}
