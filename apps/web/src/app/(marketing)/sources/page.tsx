import type { Metadata } from "next";
import Link from "next/link";
import { ConnectorMark } from "@/components/ConnectorMark";
import { JsonLd } from "@/components/JsonLd";
import { FaqSection, type FaqEntry } from "@/lib/faq";
import { faqPageJsonLd, graph, itemListJsonLd } from "@/lib/jsonld";
import { metricPages, sourceGroups, sourcePages } from "@/lib/sources";
import { absoluteUrl } from "@/lib/site";

// `sourceGroups()` is a pure read of the provider manifests, but the metric
// pages it links to are built with `node:fs` sidecars. Static, like the rest
// of this tree.
export const dynamic = "force-static";

const FAQ: FaqEntry[] = [
  {
    question: "What is a source in Notch Metrics?",
    answer:
      "A source is a service Notch Metrics reads a number from: Stripe, Shopify, Plausible, GitHub and the rest. You connect it once on the web, and every Mac you sign in to picks the connection up.",
  },
  {
    question: "Do I pay per source?",
    answer:
      "No. Every connector is included on both plans, with no per-integration charge. Notch Metrics is $14 a month or $79 a year, after a seven-day trial that needs no card.",
  },
  {
    question: "Does my API key reach my Mac?",
    answer:
      "No. Our server calls the provider and hands the Mac app a normalised number. Each credential is encrypted with its own key, bound to your account and the provider, so a row copied anywhere else does not decrypt.",
  },
  {
    question: "What if the number I want has no source here?",
    answer:
      "Write a custom metric. The Notch Metrics MCP server lets a coding agent write one JavaScript module against any HTTPS API, and it runs on your Mac with its keys in the Keychain.",
  },
  {
    question: "How often do sources update?",
    answer:
      "Each metric is fetched and normalised on a schedule, so the notch holds a recent figure rather than calling the provider every time you look. Hover the camera housing and the number is already there.",
  },
];

export const metadata: Metadata = {
  title: "Sources",
  description:
    "Every service Notch Metrics reads a number from, and every number it reports. Revenue, analytics, SEO and developer sources, in the MacBook notch.",
  alternates: { canonical: "/sources" },
  openGraph: { url: absoluteUrl("/sources") },
};

export default function SourcesIndex() {
  const groups = sourceGroups();
  const sources = sourcePages();
  const metrics = metricPages();

  const jsonLd = graph(
    itemListJsonLd(
      sources.map(({ manifest, path }) => ({ name: manifest.name, path })),
      "/sources",
    ),
    faqPageJsonLd(FAQ, "/sources"),
  );

  return (
    <main className="relative isolate mx-auto max-w-5xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />
      <div className="hero-glow" />

      <p className="eyebrow">Sources</p>
      <h1 className="mt-4 text-balance text-[2.125rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.75rem]">
        Every number Notch Metrics can show you
      </h1>
      <p className="mt-5 max-w-2xl text-pretty text-[17px] leading-relaxed text-white/55">
        {sources.length} sources and {metrics.length} numbers. Connect one on the web, place the
        widget in the notch, and it is there on every Mac you sign in to.
      </p>

      <div className="mt-16 flex flex-col gap-14">
        {groups.map((group) => (
          <section key={group.category}>
            <h2 className="text-sm font-medium text-white/70">{group.label}</h2>
            <ul className="mt-5 grid gap-3 sm:grid-cols-2">
              {group.manifests.map((manifest) => (
                <li key={manifest.id}>
                  <Link
                    href={`/sources/${manifest.id}`}
                    className="panel flex h-full items-start gap-4 p-5 transition hover:bg-white/[0.05]"
                  >
                    <ConnectorMark
                      id={manifest.id}
                      name={manifest.name}
                      accentColor={manifest.accentColor}
                      size={40}
                    />
                    <span className="flex flex-col gap-1.5">
                      <span className="flex items-center gap-2 text-[15px] font-medium">
                        {manifest.name}
                        {manifest.status === "beta" && (
                          <span className="rounded-full border border-white/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-white/40">
                            Beta
                          </span>
                        )}
                      </span>
                      <span className="text-sm leading-relaxed text-white/50">
                        {manifest.tagline}
                      </span>
                      <span className="font-mono text-[11px] tracking-wide text-white/30">
                        {manifest.metrics.length}{" "}
                        {manifest.metrics.length === 1 ? "number" : "numbers"}
                      </span>
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>

      <FaqSection entries={FAQ} />
    </main>
  );
}
