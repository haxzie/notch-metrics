import { z } from "zod";
import { BaseFrontmatter, type BaseEntry, readCollection, tagsOf } from "@/lib/collection";

export { formatDate, lastModified } from "@/lib/collection";

/**
 * The blog, read from `content/blog/*.md` at build time.
 *
 * The parser, the renderer and the shared frontmatter live in
 * `src/lib/collection.ts`; this file is the blog's own schema and its
 * queries. See that module for the `node:fs` constraint that governs every
 * route calling into here.
 */
const Frontmatter = BaseFrontmatter.extend({
  /**
   * The slug of the post this one sits under. Absent means this post *is* a
   * pillar.
   *
   * One field, read in both directions: the child renders a "Part of" link up
   * to its pillar, and the pillar renders a "Read next" list of its children.
   * Two fields pointing at each other is how a cluster ends up claiming a
   * parent that does not claim it back.
   */
  pillar: z.string().min(1).optional(),
});

export type Post = BaseEntry & z.infer<typeof Frontmatter>;

export function allPosts(): Post[] {
  return readCollection("blog", Frontmatter);
}

export function postBySlug(slug: string): Post | undefined {
  return allPosts().find((post) => post.slug === slug);
}

/**
 * The posts sitting under one pillar, oldest first.
 *
 * Oldest first rather than newest: a cluster is read as a sequence, and the
 * first how-to under "Stripe MRR on your Mac" should be the one to start
 * with, not the one written most recently.
 */
export function clusterOf(slug: string, posts: Post[] = allPosts()): Post[] {
  return posts
    .filter((post) => post.pillar === slug && !post.draft)
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** Every pillar, newest first. The posts that lead a cluster. */
export function pillars(posts: Post[] = allPosts()): Post[] {
  return posts.filter((post) => !post.pillar);
}

/**
 * Every tag in use, most-used first, ties broken alphabetically.
 *
 * The count is returned but not rendered — it is the sort key, so the index
 * leads with the subjects the blog actually covers rather than with whichever
 * tag happens to sort first.
 */
export function allTags(posts: Post[] = allPosts()): { tag: string; count: number }[] {
  return tagsOf(posts);
}
