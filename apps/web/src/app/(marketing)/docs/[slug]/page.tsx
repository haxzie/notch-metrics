import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { JsonLd } from "@/components/JsonLd";
import { DocsSidebar } from "@/components/marketing/DocsSidebar";
import { PostToc } from "@/components/marketing/PostToc";
import {
  SECTION_LABELS,
  allDocs,
  docBySlug,
  docNeighbours,
  lastModified,
  sidebarGroups,
} from "@/lib/docs";
import { breadcrumbJsonLd, graph } from "@/lib/jsonld";
import { LLM_ALTERNATES, absoluteUrl } from "@/lib/site";

// Read with `node:fs` at build time — see the note in src/lib/collection.ts.
export const dynamic = "force-static";
// A slug that is not a file 404s instead of being rendered on demand, which
// on the Worker would mean a runtime `fs` read that cannot succeed.
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allDocs().map((doc) => ({ slug: doc.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const doc = docBySlug(slug);
  if (!doc) return {};

  const url = absoluteUrl(`/docs/${doc.slug}`);

  return {
    title: doc.title,
    description: doc.description,
    alternates: { canonical: `/docs/${doc.slug}`, types: LLM_ALTERNATES },
    robots: doc.draft ? { index: false, follow: false } : undefined,
    openGraph: {
      type: "article",
      url,
      title: doc.title,
      description: doc.description,
      modifiedTime: lastModified(doc),
    },
    twitter: { card: "summary_large_image", title: doc.title, description: doc.description },
  };
}

export default async function DocPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const doc = docBySlug(slug);
  if (!doc) notFound();

  const path = `/docs/${doc.slug}`;
  const { previous, next } = docNeighbours(doc.slug);

  const jsonLd = graph(
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Docs", path: "/docs" },
        { name: doc.title, path },
      ],
      path,
    ),
  );

  // Two headings is a list that repeats the page, which is why the blog uses
  // the same floor.
  const toc = doc.headings.length > 2 ? doc.headings : [];

  return (
    /* The blog's measure, with the docs rail in place of its cluster rail.
       Below `xl` both rails fold away and the body runs full width. */
    <main className="relative isolate mx-auto grid max-w-[88rem] grid-cols-1 gap-x-12 px-6 pb-20 pt-36 xl:grid-cols-[14rem_minmax(0,50rem)_17rem] xl:justify-center">
      <JsonLd data={jsonLd} />
      <DocsSidebar groups={sidebarGroups()} />

      {/* The measure, held below `xl` as well as at it. Without this the
          single-column fallback stretched the prose across the full 82rem. */}
      <article className="mx-auto w-full max-w-[50rem] xl:mx-0 xl:max-w-none">
        <p className="eyebrow">{SECTION_LABELS[doc.section]}</p>
        <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight">{doc.title}</h1>
        <p className="text-ink/60 mt-5 text-pretty text-lg leading-relaxed">{doc.description}</p>

        {toc.length > 0 && (
          <div className="border-ink/[0.08] bg-ink/[0.02] mt-8 rounded-2xl border p-4 xl:hidden">
            <p className="eyebrow">On this page</p>
            <ul className="mt-2 space-y-1.5">
              {toc.map((heading) => (
                <li key={heading.id}>
                  <a href={`#${heading.id}`} className="text-ink/60 hover:text-ink text-[13.5px]">
                    {heading.text}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="prose mt-10" dangerouslySetInnerHTML={{ __html: doc.html }} />

        <nav
          aria-label="More documentation"
          className="border-ink/[0.07] mt-16 grid gap-3 border-t pt-8 sm:grid-cols-2"
        >
          {previous ? (
            <Link
              href={`/docs/${previous.slug}`}
              className="panel hover:border-ink/15 hover:bg-ink/[0.05] p-4 transition"
            >
              <span className="eyebrow">Previous</span>
              <span className="mt-1.5 block text-[15px] font-semibold tracking-tight">
                {previous.title}
              </span>
            </Link>
          ) : (
            <span />
          )}
          {next && (
            <Link
              href={`/docs/${next.slug}`}
              className="panel hover:border-ink/15 hover:bg-ink/[0.05] p-4 text-right transition sm:col-start-2"
            >
              <span className="eyebrow">Next</span>
              <span className="mt-1.5 block text-[15px] font-semibold tracking-tight">
                {next.title}
              </span>
            </Link>
          )}
        </nav>
      </article>

      {toc.length > 0 ? <PostToc headings={toc} /> : <div />}
    </main>
  );
}
