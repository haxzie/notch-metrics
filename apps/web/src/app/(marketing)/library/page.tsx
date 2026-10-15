import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { FaqSection, type FaqEntry } from "@/lib/faq";
import { faqPageJsonLd, graph, itemListJsonLd } from "@/lib/jsonld";
import { allLibraryEntries, libraryGroups } from "@/lib/library";
import { LLM_ALTERNATES, absoluteUrl } from "@/lib/site";

const TITLE = "Content library";
const DESCRIPTION =
  "The reference shelf: roundups of the tools in this category, alternatives worth knowing, and plain definitions of the numbers a founder tracks.";

// The meta description names the shelf because a search result has no
// heading above it. The page already has one, so the lede does not repeat it.
const LEDE =
  "Roundups of the tools in this category, alternatives worth knowing, and plain definitions of the numbers a founder tracks.";

// `content/library` is read with `node:fs` — see src/lib/collection.ts.
export const dynamic = "force-static";

const FAQ: FaqEntry[] = [
  {
    question: "What is in the Notch Metrics content library?",
    answer:
      "Three kinds of page: roundups comparing the tools in this category, alternatives to the better-known ones, and a glossary defining the numbers a founder tracks, such as MRR, churn and average order value.",
  },
  {
    question: "How is the library different from the blog?",
    answer:
      "The blog is how-tos you follow, step by step, usually against a provider's API. The library is reference: you arrive from a search, get the definition or the comparison, and leave. Keeping them apart stops a definition competing with the guide that uses it.",
  },
  {
    question: "Are the prices in the comparisons current?",
    answer:
      "Every comparison carries the date its prices were read off each vendor's own pricing page. Prices move, so check the date at the top of the table before quoting a figure from it.",
  },
];

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/library", types: LLM_ALTERNATES },
  openGraph: {
    type: "website",
    url: absoluteUrl("/library"),
    title: TITLE,
    description: DESCRIPTION,
  },
};

export default function LibraryIndex() {
  const entries = allLibraryEntries();
  const groups = libraryGroups(entries);

  const jsonLd = graph(
    itemListJsonLd(
      entries.map((entry) => ({ name: entry.title, path: `/library/${entry.slug}` })),
      "/library",
    ),
    faqPageJsonLd(FAQ, "/library"),
  );

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />

      <p className="eyebrow">Library</p>
      <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
        The reference <span className="accent">shelf</span>
      </h1>
      <p className="text-ink/60 mt-5 max-w-xl text-pretty text-lg leading-relaxed">{LEDE}</p>

      {entries.length === 0 ? (
        <p className="text-ink/40 mt-16">Nothing here yet.</p>
      ) : (
        <div className="mt-14 flex flex-col gap-12">
          {groups.map((group) => (
            <section key={group.kind}>
              <h2 className="text-ink/70 text-sm font-medium">{group.label}</h2>
              <ul className="mt-5 flex flex-col gap-3">
                {group.entries.map((entry) => (
                  <li key={entry.slug}>
                    <Link
                      href={`/library/${entry.slug}`}
                      className="panel hover:border-ink/15 hover:bg-ink/[0.05] group block p-5 transition"
                    >
                      <h3 className="group-hover:text-ink text-pretty text-[17px] font-semibold tracking-tight transition">
                        {entry.title}
                      </h3>
                      <p className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">
                        {entry.description}
                      </p>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      )}

      <FaqSection entries={FAQ} />
    </main>
  );
}
