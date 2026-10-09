import type { MetadataRoute } from "next";
import { allPosts, lastModified } from "@/lib/blog";
import { LEGAL_UPDATED } from "@/lib/legal";
import { SITE_URL } from "@/lib/site";

// `allPosts()` reads the filesystem — see the note in src/lib/blog.ts.
export const dynamic = "force-static";

/**
 * Only canonical, indexable, 200-returning URLs belong here.
 *
 * Deliberately absent:
 * - `/pricing`, which is a redirect to `/#pricing`. A sitemap full of
 *   redirects is how a site teaches a crawler that its sitemap is unreliable.
 * - `/download`, a route handler that 302s to the current DMG.
 * - `/app`, `/login`, `/connect/*`, `/desktop/*` — signed-in or single-use.
 *
 * `lastModified` is given only where we actually know it. An invented date
 * that moves on every deploy is worse than none: it asks for a re-crawl of
 * every page every time and gets the whole file discounted.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const posts = allPosts().filter((post) => !post.draft);

  const newestPost = posts[0];

  return [
    {
      url: SITE_URL,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${SITE_URL}/blog`,
      // The index changes exactly when its newest post does.
      lastModified: newestPost ? lastModified(newestPost) : undefined,
      changeFrequency: "weekly",
      priority: 0.8,
    },
    ...posts.map((post) => ({
      url: `${SITE_URL}/blog/${post.slug}`,
      lastModified: lastModified(post),
      changeFrequency: "yearly" as const,
      priority: 0.7,
    })),
    {
      url: `${SITE_URL}/download/manual`,
      changeFrequency: "monthly",
      priority: 0.5,
    },
    {
      url: `${SITE_URL}/privacy`,
      lastModified: LEGAL_UPDATED.privacy,
      changeFrequency: "yearly",
      priority: 0.3,
    },
    {
      url: `${SITE_URL}/terms`,
      lastModified: LEGAL_UPDATED.terms,
      changeFrequency: "yearly",
      priority: 0.3,
    },
  ];
}
