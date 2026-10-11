import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { JsonLd } from "@/components/JsonLd";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { FaqSection } from "@/lib/faq";
import {
  articleJsonLd,
  breadcrumbJsonLd,
  definedTermJsonLd,
  faqPageJsonLd,
  graph,
} from "@/lib/jsonld";
import {
  KIND_LABELS,
  allLibraryEntries,
  formatDate,
  lastModified,
  libraryEntryBySlug,
} from "@/lib/library";
import { LLM_ALTERNATES, absoluteUrl } from "@/lib/site";

// Read with `node:fs` at build time — see src/lib/collection.ts.
export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allLibraryEntries().map((entry) => ({ slug: entry.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const entry = libraryEntryBySlug(slug);
  if (!entry) return {};

  const path = `/library/${entry.slug}`;

  return {
    title: entry.title,
    description: entry.description,
    alternates: { canonical: path, types: LLM_ALTERNATES },
    keywords: entry.tags,
    robots: entry.draft ? { index: false, follow: false } : undefined,
    openGraph: {
      type: "article",
      url: absoluteUrl(path),
      title: entry.title,
      description: entry.description,
      publishedTime: entry.date,
      modifiedTime: lastModified(entry),
      tags: entry.tags,
    },
  };
}

export default async function LibraryPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const entry = libraryEntryBySlug(slug);
  if (!entry) notFound();

  const path = `/library/${entry.slug}`;

  const jsonLd = graph(
    articleJsonLd(entry, { path, modified: lastModified(entry), collection: "/library#library" }),
    // A glossary entry is a defined term as well as an article. The two
    // describe the same page from different angles, which is what `@graph`
    // is for.
    entry.kind === "glossary" && entry.term
      ? definedTermJsonLd({
          name: entry.term,
          description: entry.description,
          path,
          setName: "Notch Metrics glossary",
          setPath: "/library",
        })
      : null,
    faqPageJsonLd(entry.faq, path),
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Library", path: "/library" },
        { name: entry.title, path },
      ],
      path,
    ),
  );

  return (
    <main className="relative isolate mx-auto max-w-2xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />
      <div className="hero-glow" />

      <nav aria-label="Breadcrumb" className="font-mono text-[11px] tracking-wide text-white/40">
        <ol className="flex items-center gap-2">
          <li>
            <Link href="/" className="transition hover:text-white">
              Home
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href="/library" className="transition hover:text-white">
              Library
            </Link>
          </li>
        </ol>
      </nav>

      <article className="mt-6">
        <p className="eyebrow">{KIND_LABELS[entry.kind]}</p>
        <h1 className="mt-3 text-balance text-[2.125rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.75rem]">
          {entry.title}
        </h1>

        <div className="mt-5 flex flex-wrap items-center gap-x-2.5 font-mono text-[11px] tracking-wide text-white/40">
          <time dateTime={entry.date}>{formatDate(entry.date)}</time>
          <span aria-hidden>·</span>
          <span>{entry.readingMinutes} min read</span>
          {entry.verifiedOn && (
            <>
              <span aria-hidden>·</span>
              <span>prices checked {entry.verifiedOn}</span>
            </>
          )}
        </div>

        {entry.headings.length > 2 && (
          <nav aria-label="On this page" className="panel mt-10 p-5">
            <p className="eyebrow">On this page</p>
            <ul className="mt-3 flex flex-col gap-1.5">
              {entry.headings.map((heading) => (
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
          // on sanitisation in src/lib/collection.ts.
          dangerouslySetInnerHTML={{ __html: entry.html }}
        />
      </article>

      <FaqSection entries={entry.faq} />

      <aside className="panel mt-16 flex flex-col items-start gap-4 p-7">
        <h2 className="text-lg font-semibold tracking-tight">Your numbers, in the notch</h2>
        <p className="text-[15px] leading-relaxed text-white/55">
          Notch Metrics puts revenue, MRR and subscribers in the MacBook notch. Hover to look, move
          away and it is gone. Seven days of everything, with no card.
        </p>
        <DownloadButton />
      </aside>
    </main>
  );
}
