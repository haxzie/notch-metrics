import type { MetadataRoute } from "next";
import { allPosts, lastModified } from "@/lib/blog";
import { LEGAL_UPDATED } from "@/lib/legal";
import { allLibraryEntries } from "@/lib/library";
import { SITE_URL } from "@/lib/site";
import { metricPages, sourcePages } from "@/lib/sources";
import { allTools } from "@/lib/tools";

// `allPosts()` reads the filesystem — see the note in src/lib/collection.ts.
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
 * every page every time and gets the whole file discounted. That is why the
 * `/sources` entries below carry none — they are generated from the provider
 * manifests and have no meaningful modification date of their own.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const posts = allPosts().filter((post) => !post.draft);
  const library = allLibraryEntries().filter((entry) => !entry.draft);
  const sources = sourcePages();
  const metrics = metricPages();
  const tools = allTools();

  const newestPost = posts[0];
  const newestLibrary = library[0];

  return [
    {
      url: SITE_URL,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${SITE_URL}/sources`,
      changeFrequency: "weekly",
      priority: 0.9,
    },
    ...sources.map((source) => ({
      url: `${SITE_URL}${source.path}`,
      changeFrequency: "monthly" as const,
      priority: 0.8,
    })),
    ...metrics.map((metric) => ({
      url: `${SITE_URL}${metric.path}`,
      changeFrequency: "monthly" as const,
      priority: 0.6,
    })),
    {
      url: `${SITE_URL}/free-tools`,
      changeFrequency: "monthly",
      priority: 0.8,
    },
    ...tools.map((tool) => ({
      url: `${SITE_URL}/free-tools/${tool.slug}`,
      changeFrequency: "monthly" as const,
      priority: 0.7,
    })),
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
      url: `${SITE_URL}/library`,
      lastModified: newestLibrary ? lastModified(newestLibrary) : undefined,
      changeFrequency: "weekly",
      priority: 0.6,
    },
    ...library.map((entry) => ({
      url: `${SITE_URL}/library/${entry.slug}`,
      lastModified: lastModified(entry),
      changeFrequency: "yearly" as const,
      priority: 0.5,
    })),
    {
      url: `${SITE_URL}/security`,
      changeFrequency: "yearly",
      priority: 0.5,
    },
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
