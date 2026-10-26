import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { CopyPrompt } from "@/components/marketing/CopyPrompt";
import { DocsSidebar } from "@/components/marketing/DocsSidebar";
import { docGroups, sidebarGroups } from "@/lib/docs";
import { BUILD_PROMPT } from "@/lib/docs-llms";
import { breadcrumbJsonLd, graph } from "@/lib/jsonld";
import { LLM_ALTERNATES, absoluteUrl } from "@/lib/site";

// Read with `node:fs` at build time — see the note in src/lib/collection.ts.
export const dynamic = "force-static";

const TITLE = "Custom apps and widgets";
const DESCRIPTION =
  "What a widget is, the shapes it draws, and how to build a custom app that puts your own numbers in the notch.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/docs", types: LLM_ALTERNATES },
  openGraph: { type: "website", url: absoluteUrl("/docs"), title: TITLE, description: DESCRIPTION },
};

export default function DocsIntroduction() {
  const groups = docGroups();

  const jsonLd = graph(
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Docs", path: "/docs" },
      ],
      "/docs",
    ),
  );

  return (
    <main className="relative isolate mx-auto grid max-w-[88rem] grid-cols-1 gap-x-12 px-6 pb-20 pt-36 xl:grid-cols-[14rem_minmax(0,52rem)] xl:justify-center">
      <JsonLd data={jsonLd} />
      <DocsSidebar groups={sidebarGroups()} />

      {/* The measure, held below `xl` as well as at it. Without this the
          single-column fallback stretched the prose across the full 82rem, so
          a 1279px window drew a 1231px line where the blog draws 672px. */}
      <div className="mx-auto w-full max-w-[52rem] xl:mx-0 xl:max-w-none">
        <p className="eyebrow">Introduction</p>
        <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
          Custom apps and <span className="accent">widgets</span>
        </h1>
        <p className="text-ink/60 mt-5 text-pretty text-lg leading-relaxed">
          A widget is one tile in the notch. It carries a number, how that number moved, and nothing
          else. Notch Metrics ships widgets for sixteen services. For anything else you write a
          custom app, which runs on your Mac against your own key.
        </p>

        <div className="mt-10">
          <CopyPrompt prompt={BUILD_PROMPT} href="/docs/llms.txt" />
        </div>

        <section className="mt-14">
          <h2 className="text-ink/70 text-sm font-medium">Where to start</h2>
          <ul className="mt-5 grid gap-3 sm:grid-cols-2">
            <li>
              <Link
                href="/docs/quickstart"
                className="panel hover:border-ink/15 hover:bg-ink/[0.05] group flex h-full flex-col p-5 transition"
              >
                <span className="group-hover:text-ink text-pretty text-[17px] font-semibold tracking-tight transition">
                  Build one now
                </span>
                <span className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">
                  A folder, two files, and a widget in the notch in about ten minutes.
                </span>
              </Link>
            </li>
            <li>
              <Link
                href="/docs/what-is-a-widget"
                className="panel hover:border-ink/15 hover:bg-ink/[0.05] group flex h-full flex-col p-5 transition"
              >
                <span className="group-hover:text-ink text-pretty text-[17px] font-semibold tracking-tight transition">
                  Learn the pieces
                </span>
                <span className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">
                  What a widget is made of, and the seven shapes a tile draws.
                </span>
              </Link>
            </li>
          </ul>
        </section>

        {groups.map((group) => (
          <section key={group.section} className="mt-12">
            <h2 className="text-ink/70 text-sm font-medium">{group.label}</h2>
            <ul className="mt-5 grid gap-3 sm:grid-cols-2">
              {group.docs.map((doc) => (
                <li key={doc.slug}>
                  <Link
                    href={`/docs/${doc.slug}`}
                    className="panel hover:border-ink/15 hover:bg-ink/[0.05] group flex h-full flex-col p-5 transition"
                  >
                    <span className="group-hover:text-ink text-pretty text-[17px] font-semibold tracking-tight transition">
                      {doc.title}
                    </span>
                    <span className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">
                      {doc.summary}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </main>
  );
}
