import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { allPosts, formatDate, lastModified, postBySlug } from "@/lib/blog";
import { LLM_ALTERNATES, SITE_NAME, absoluteUrl } from "@/lib/site";

// Read with `node:fs` at build time — see the note in src/lib/blog.ts.
export const dynamic = "force-static";
// A slug that is not a file 404s instead of being rendered on demand, which
// on the Worker would mean a runtime `fs` read that cannot succeed.
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allPosts().map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) return {};

  const url = absoluteUrl(`/blog/${post.slug}`);

  return {
    title: post.title,
    description: post.description,
    // Absolute and explicit. Without it a post is reachable at its own URL and
    // at any tracking-parameter variant of it, and the variants compete.
    alternates: { canonical: `/blog/${post.slug}`, types: LLM_ALTERNATES },
    keywords: post.tags,
    authors: [{ name: post.author }],
    // A draft is live at its real URL so it can be reviewed there, but it must
    // not be indexed before it is announced.
    robots: post.draft ? { index: false, follow: false } : undefined,
    openGraph: {
      type: "article",
      url,
      title: post.title,
      description: post.description,
      publishedTime: post.date,
      modifiedTime: lastModified(post),
      authors: [post.author],
      tags: post.tags,
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description: post.description,
    },
  };
}

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) notFound();

  // Newest first, so the *next* post chronologically is the previous index.
  const posts = allPosts();
  const index = posts.findIndex((p) => p.slug === post.slug);
  const newer = index > 0 ? posts[index - 1] : undefined;
  const older = index >= 0 ? posts[index + 1] : undefined;

  const url = absoluteUrl(`/blog/${post.slug}`);
  const publisher = { "@type": "Organization", name: SITE_NAME, url: absoluteUrl("/") };

  /**
   * `BlogPosting` and a `BreadcrumbList`, in one graph.
   *
   * `mainEntityOfPage` pointing back at the canonical URL is what stops a
   * syndicated or scraped copy of the text from being read as the original.
   */
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "BlogPosting",
        "@id": `${url}#post`,
        headline: post.title,
        description: post.description,
        url,
        mainEntityOfPage: { "@type": "WebPage", "@id": url },
        datePublished: post.date,
        dateModified: lastModified(post),
        author: { "@type": "Organization", name: post.author, url: absoluteUrl("/") },
        publisher,
        isPartOf: { "@type": "Blog", "@id": absoluteUrl("/blog#blog") },
        keywords: post.tags.join(", "),
        wordCount: post.markdown.split(/\s+/).filter(Boolean).length,
        inLanguage: "en",
      },
      {
        "@type": "BreadcrumbList",
        "@id": `${url}#breadcrumbs`,
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Home", item: absoluteUrl("/") },
          { "@type": "ListItem", position: 2, name: "Blog", item: absoluteUrl("/blog") },
          { "@type": "ListItem", position: 3, name: post.title, item: url },
        ],
      },
    ],
  };

  return (
    <main className="relative isolate mx-auto max-w-2xl px-6 pb-16 pt-36">
      <script
        type="application/ld+json"
        // Our own strings, assembled above — not user input.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <div className="hero-glow" />

      {/* Visible breadcrumbs as well as the structured kind: the markup tells a
          crawler where the page sits, this tells a reader who arrived from a
          search result for one paragraph in the middle. */}
      <nav aria-label="Breadcrumb" className="font-mono text-[11px] tracking-wide text-white/40">
        <ol className="flex items-center gap-2">
          <li>
            <Link href="/" className="transition hover:text-white">
              Home
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href="/blog" className="transition hover:text-white">
              Blog
            </Link>
          </li>
        </ol>
      </nav>

      <article className="mt-6">
        <h1 className="text-balance text-[2.125rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.75rem]">
          {post.title}
        </h1>

        <div className="mt-5 flex flex-wrap items-center gap-x-2.5 font-mono text-[11px] tracking-wide text-white/40">
          <span>{post.author}</span>
          <span aria-hidden>·</span>
          <time dateTime={post.date}>{formatDate(post.date)}</time>
          <span aria-hidden>·</span>
          <span>{post.readingMinutes} min read</span>
          {post.updated && (
            <>
              <span aria-hidden>·</span>
              <span>
                updated <time dateTime={post.updated}>{formatDate(post.updated)}</time>
              </span>
            </>
          )}
        </div>

        {post.headings.length > 2 && (
          <nav aria-label="On this page" className="panel mt-10 p-5">
            <p className="eyebrow">On this page</p>
            <ul className="mt-3 flex flex-col gap-1.5">
              {post.headings.map((heading) => (
                <li key={heading.id}>
                  <a
                    href={`#${heading.id}`}
                    className="text-[14px] text-white/55 transition hover:text-white"
                  >
                    {heading.text}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        )}

        <div
          className="prose mt-10"
          // Rendered from markdown committed to this repository. See the note
          // on sanitisation in src/lib/blog.ts.
          dangerouslySetInnerHTML={{ __html: post.html }}
        />

        {post.tags.length > 0 && (
          <ul className="mt-12 flex flex-wrap gap-2">
            {post.tags.map((tag) => (
              <li
                key={tag}
                className="rounded-full border border-white/10 bg-white/[0.04] px-3 py-1 font-mono text-[11px] tracking-wide text-white/50"
              >
                {tag}
              </li>
            ))}
          </ul>
        )}
      </article>

      {(newer || older) && (
        <nav
          aria-label="More posts"
          className="mt-16 grid gap-3 border-t border-white/[0.06] pt-10 sm:grid-cols-2"
        >
          {older && <AdjacentPost post={older} label="Older" />}
          {newer && <AdjacentPost post={newer} label="Newer" align="right" />}
        </nav>
      )}
    </main>
  );
}

function AdjacentPost({
  post,
  label,
  align = "left",
}: {
  post: { slug: string; title: string };
  label: string;
  align?: "left" | "right";
}) {
  return (
    <Link
      href={`/blog/${post.slug}`}
      className={`panel p-5 transition hover:border-white/15 hover:bg-white/[0.05] ${
        align === "right" ? "sm:col-start-2 sm:text-right" : ""
      }`}
    >
      <span className="eyebrow">{label}</span>
      <span className="mt-2 block text-pretty text-[15px] font-medium leading-snug">
        {post.title}
      </span>
    </Link>
  );
}
