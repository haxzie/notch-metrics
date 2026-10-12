import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { FaqSection, type FaqEntry } from "@/lib/faq";
import { faqPageJsonLd, graph, itemListJsonLd } from "@/lib/jsonld";
import { absoluteUrl } from "@/lib/site";
import { allTools, toolGroups } from "@/lib/tools";

const TITLE = "Free tools";
const DESCRIPTION =
  "Free calculators for the numbers a founder tracks: MRR, ARR, churn, lifetime value, average order value, CTR and payment fees. No signup.";

const FAQ: FaqEntry[] = [
  {
    question: "Are these calculators really free?",
    answer:
      "Yes. There is no signup, no email wall and no limit on use. They run entirely in your browser, so nothing you type is sent anywhere or stored.",
  },
  {
    question: "Do the calculators store the numbers I enter?",
    answer:
      "No. Every calculation happens in your browser. The figures you type never reach a server, which is why there is nothing to sign up for.",
  },
  {
    question: "Which calculator should I use for subscription revenue?",
    answer:
      "Start with the MRR calculator for the value of your book, then the churn rate calculator and lifetime value calculator to understand what a customer is worth. Net revenue retention is the one investors ask for.",
  },
  {
    question: "Can I see these numbers automatically instead of calculating them?",
    answer:
      "Yes, that is what Notch Metrics does. Connect Stripe, Polar, Shopify or any of fourteen sources and the figures sit in your MacBook notch, updated on a schedule, with no tab to open.",
  },
];

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/free-tools" },
  openGraph: {
    type: "website",
    url: absoluteUrl("/free-tools"),
    title: TITLE,
    description: DESCRIPTION,
  },
};

export default function FreeToolsIndex() {
  const groups = toolGroups();
  const tools = allTools();

  const jsonLd = graph(
    itemListJsonLd(
      tools.map((tool) => ({ name: tool.name, path: `/free-tools/${tool.slug}` })),
      "/free-tools",
    ),
    faqPageJsonLd(FAQ, "/free-tools"),
  );

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />
      <div className="hero-glow" />

      <p className="eyebrow">Free tools</p>
      <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
        Calculators for the numbers you <span className="accent">track</span>
      </h1>
      <p className="mt-5 max-w-xl text-pretty text-lg leading-relaxed text-white/60">
        {tools.length} free calculators, no signup. Each one runs in your browser and explains the
        formula, what it leaves out, and where the figure usually goes wrong.
      </p>

      <div className="mt-14 flex flex-col gap-12">
        {groups.map((group) => (
          <section key={group.category}>
            <h2 className="text-sm font-medium text-white/70">{group.label}</h2>
            <ul className="panel mt-5 overflow-hidden">
              {group.tools.map((tool) => (
                <li key={tool.slug} className="border-t border-white/[0.07] first:border-t-0">
                  <Link
                    href={`/free-tools/${tool.slug}`}
                    className="group block px-6 py-5 transition hover:bg-white/[0.04] sm:px-7"
                  >
                    <h3 className="text-[17px] font-semibold tracking-tight transition group-hover:text-white">
                      {tool.name}
                    </h3>
                    <p className="mt-1.5 text-pretty text-[15px] leading-relaxed text-white/55">
                      {tool.description}
                    </p>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>

      <FaqSection entries={FAQ} />

      <aside className="panel mt-16 flex flex-col items-start gap-4 p-7">
        <h2 className="text-lg font-semibold tracking-tight">Stop calculating these by hand</h2>
        <p className="text-[15px] leading-relaxed text-white/55">
          Notch Metrics reads MRR, revenue, churn and more from{" "}
          <Link href="/sources">fourteen sources</Link> and puts them in the MacBook notch. Hover
          the camera housing to look, move away and it is gone.
        </p>
        <Link
          href="/download"
          className="inline-flex h-10 items-center rounded-full bg-white px-5 text-sm font-semibold text-black transition hover:bg-white/90"
        >
          Download for Mac
        </Link>
      </aside>
    </main>
  );
}
