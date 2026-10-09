import type { Metadata } from "next";
import Link from "next/link";
import { allPosts, allTags, formatDate } from "@/lib/blog";
import { LLM_ALTERNATES, SITE_NAME, absoluteUrl } from "@/lib/site";

const TITLE = "Blog";
const DESCRIPTION =
  "Notes on building Notch Metrics: the notch itself, how we handle your provider keys, and guides to getting any number you care about onto your Mac.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/blog", types: LLM_ALTERNATES },
  openGraph: {
    type: "website",
    url: absoluteUrl("/blog"),
    title: `${TITLE} · ${SITE_NAME}`,
    description: DESCRIPTION,
  },
};

// `content/blog` is read with `node:fs`, which the Worker this deploys to does
// not have. Forcing static keeps that read inside `next build`.
export const dynamic = "force-static";

export default function BlogIndex() {
  const posts = allPosts();
  const tags = allTags(posts);

  /**
   * `Blog` plus the posts as an `ItemList`.
   *
   * The list is what gets a listing page treated as a hub rather than as
   * three paragraphs of boilerplate — it tells a crawler the page's purpose
   * is the links, and in what order they belong.
   */
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Blog",
    "@id": absoluteUrl("/blog#blog"),
    name: `${SITE_NAME} blog`,
    description: DESCRIPTION,
    url: absoluteUrl("/blog"),
    publisher: { "@type": "Organization", name: SITE_NAME, url: absoluteUrl("/") },
    blogPost: posts.map((post) => ({
      "@type": "BlogPosting",
      "@id": absoluteUrl(`/blog/${post.slug}#post`),
      headline: post.title,
      description: post.description,
      url: absoluteUrl(`/blog/${post.slug}`),
      datePublished: post.date,
      dateModified: post.updated ?? post.date,
      author: { "@type": "Organization", name: post.author },
      keywords: post.tags.join(", "),
    })),
  };

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <script
        type="application/ld+json"
        // Our own strings, assembled above — not user input.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <div className="hero-glow" />

      <p className="eyebrow">Blog</p>
      <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
        Notes from the <span className="accent">notch</span>
      </h1>
      <p className="mt-5 max-w-xl text-pretty text-lg leading-relaxed text-white/60">
        {DESCRIPTION}
      </p>

      {tags.length > 0 && (
        <ul className="mt-8 flex flex-wrap gap-2">
          {tags.map(({ tag }) => (
            <li
              key={tag}
              className="rounded-full border border-white/10 bg-white/[0.04] px-3 py-1 font-mono text-[11px] tracking-wide text-white/50"
            >
              {tag}
            </li>
          ))}
        </ul>
      )}

      {posts.length === 0 ? (
        <p className="mt-16 text-white/40">Nothing published yet.</p>
      ) : (
        <ul className="mt-14 flex flex-col gap-3">
          {posts.map((post) => (
            <li key={post.slug}>
              <Link
                href={`/blog/${post.slug}`}
                className="panel group block p-6 transition hover:border-white/15 hover:bg-white/[0.05] sm:p-7"
              >
                <div className="flex flex-wrap items-center gap-x-2.5 font-mono text-[11px] tracking-wide text-white/40">
                  <time dateTime={post.date}>{formatDate(post.date)}</time>
                  <span aria-hidden>·</span>
                  <span>{post.readingMinutes} min read</span>
                  {post.draft && (
                    <span className="rounded-full bg-amber-400/15 px-2 py-0.5 text-amber-300">
                      draft
                    </span>
                  )}
                </div>
                <h2 className="mt-3 text-pretty text-xl font-semibold tracking-tight transition group-hover:text-white sm:text-2xl">
                  {post.title}
                </h2>
                <p className="mt-2.5 text-pretty text-[15px] leading-relaxed text-white/55">
                  {post.description}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
