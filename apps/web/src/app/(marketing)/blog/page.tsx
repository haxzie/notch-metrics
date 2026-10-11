import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { allPosts, clusterOf, formatDate, pillars } from "@/lib/blog";
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
  // Grouped by cluster rather than listed by date. Sixty posts in one
  // reverse-chronological column buries every how-to under whichever one was
  // written last; grouped, the index reads as what the blog covers.
  const leads = pillars(posts);
  const loose = posts.filter(
    (post) => post.pillar && !leads.some((lead) => lead.slug === post.pillar),
  );

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
      <JsonLd data={jsonLd} />
      <div className="hero-glow" />

      <p className="eyebrow">Blog</p>
      <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
        Notes from the <span className="accent">notch</span>
      </h1>
      <p className="mt-5 max-w-xl text-pretty text-lg leading-relaxed text-white/60">
        {DESCRIPTION}
      </p>

      {posts.length === 0 ? (
        <p className="mt-16 text-white/40">Nothing published yet.</p>
      ) : (
        <div className="mt-14 flex flex-col gap-10">
          {leads.map((lead) => {
            const cluster = clusterOf(lead.slug, posts);
            return (
              <section key={lead.slug}>
                <Link
                  href={`/blog/${lead.slug}`}
                  className="panel group block p-6 transition hover:border-white/15 hover:bg-white/[0.05] sm:p-7"
                >
                  <div className="flex flex-wrap items-center gap-x-2.5 font-mono text-[11px] tracking-wide text-white/40">
                    <time dateTime={lead.date}>{formatDate(lead.date)}</time>
                    <span aria-hidden>·</span>
                    <span>{lead.readingMinutes} min read</span>
                    {lead.draft && (
                      <span className="rounded-full bg-amber-400/15 px-2 py-0.5 text-amber-300">
                        draft
                      </span>
                    )}
                  </div>
                  <h2 className="mt-3 text-pretty text-xl font-semibold tracking-tight transition group-hover:text-white sm:text-2xl">
                    {lead.title}
                  </h2>
                  <p className="mt-2.5 text-pretty text-[15px] leading-relaxed text-white/55">
                    {lead.description}
                  </p>
                </Link>

                {cluster.length > 0 && (
                  <ul className="mt-3 flex flex-col gap-2 border-l border-white/[0.08] pl-5">
                    {cluster.map((post) => (
                      <li key={post.slug}>
                        <Link
                          href={`/blog/${post.slug}`}
                          className="group flex flex-col gap-1 py-1.5"
                        >
                          <span className="text-[15px] font-medium text-white/80 transition group-hover:text-white">
                            {post.title}
                          </span>
                          <span className="text-sm leading-relaxed text-white/45">
                            {post.description}
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
              </section>
            );
          })}

          {/* A post naming a pillar that is not published yet still has to be
              reachable from the index, or it is an orphan nothing links to. */}
          {loose.length > 0 && (
            <ul className="flex flex-col gap-2">
              {loose.map((post) => (
                <li key={post.slug}>
                  <Link href={`/blog/${post.slug}`} className="group flex flex-col gap-1 py-1.5">
                    <span className="text-[15px] font-medium text-white/80 transition group-hover:text-white">
                      {post.title}
                    </span>
                    <span className="text-sm leading-relaxed text-white/45">
                      {post.description}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </main>
  );
}
