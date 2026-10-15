import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Calculator } from "@/components/tools/Calculator";
import { JsonLd } from "@/components/JsonLd";
import { FaqSection } from "@/lib/faq";
import { breadcrumbJsonLd, faqPageJsonLd, graph } from "@/lib/jsonld";
import { SITE_NAME, absoluteUrl } from "@/lib/site";
import { CATEGORY_LABELS, allTools, toolBySlug } from "@/lib/tools";

// The registry is plain data, so nothing here needs the filesystem. Static
// anyway, because every one of these pages is the same on every request.
export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allTools().map((tool) => ({ slug: tool.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const tool = toolBySlug(slug);
  if (!tool) return {};

  const path = `/free-tools/${tool.slug}`;

  return {
    title: `${tool.heading}, free`,
    description: tool.description,
    alternates: { canonical: path },
    openGraph: {
      type: "website",
      url: absoluteUrl(path),
      title: tool.heading,
      description: tool.description,
    },
  };
}

export default async function ToolPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const tool = toolBySlug(slug);
  if (!tool) notFound();

  const path = `/free-tools/${tool.slug}`;
  const url = absoluteUrl(path);

  const jsonLd = graph(
    /**
     * `WebApplication` with a zero-price offer.
     *
     * This is the shape a free browser tool is described with, and the offer
     * is what makes "free" machine-readable rather than only a word in the
     * title. `browserRequirements` is there because the calculator needs
     * JavaScript and saying so is honest.
     */
    {
      "@type": "WebApplication",
      "@id": `${url}#tool`,
      name: tool.heading,
      description: tool.description,
      url,
      applicationCategory: "BusinessApplication",
      operatingSystem: "Any",
      browserRequirements: "Requires JavaScript",
      isAccessibleForFree: true,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      publisher: { "@id": absoluteUrl("/#organization") },
      inLanguage: "en",
    },
    faqPageJsonLd(tool.faq, path),
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Free tools", path: "/free-tools" },
        { name: tool.name, path },
      ],
      path,
    ),
  );

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />

      <nav aria-label="Breadcrumb" className="text-ink/40 font-mono text-[11px] tracking-wide">
        <ol className="flex flex-wrap items-center gap-2">
          <li>
            <Link href="/" className="hover:text-ink transition">
              Home
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href="/free-tools" className="hover:text-ink transition">
              Free tools
            </Link>
          </li>
        </ol>
      </nav>

      <p className="eyebrow mt-6">{CATEGORY_LABELS[tool.category]}</p>
      <h1 className="mt-3 text-balance text-[2.125rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.75rem]">
        {tool.heading}
      </h1>
      <p className="text-ink/60 mt-5 text-pretty text-[17px] leading-relaxed">{tool.lede}</p>

      <Calculator slug={tool.slug} />

      {/* The prose is server-rendered and sits below the calculator. A page
          whose content only exists once JavaScript has run gives a crawler
          nothing to read, which is how a tool page ranks for nothing. */}
      <div className="mt-16 flex flex-col gap-12">
        {tool.sections.map((section) => (
          <section key={section.heading}>
            <h2 className="text-xl font-semibold tracking-tight">{section.heading}</h2>
            {section.paragraphs.map((paragraph) => (
              <p key={paragraph} className="text-ink/60 mt-4 text-[15px] leading-relaxed">
                {paragraph}
              </p>
            ))}
          </section>
        ))}
      </div>

      <FaqSection entries={tool.faq} />

      {tool.related.length > 0 && (
        <section className="border-ink/[0.06] mt-16 border-t pt-10">
          <h2 className="text-xl font-semibold tracking-tight">Related</h2>
          <ul className="mt-5 flex flex-col gap-2.5">
            {tool.related.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className="text-ink/70 hover:text-ink text-[15px] underline-offset-4 transition hover:underline"
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <aside className="panel mt-16 flex flex-col items-start gap-4 p-7">
        <h2 className="text-lg font-semibold tracking-tight">Or never calculate it again</h2>
        <p className="text-ink/55 text-[15px] leading-relaxed">
          {SITE_NAME} reads these numbers from{" "}
          <Link href="/sources">Stripe, Polar, Shopify and eleven more</Link>, and keeps them in the
          MacBook notch. Seven days of everything, with no card.
        </p>
        <Link
          href="/download"
          className="bg-ink hover:bg-ink/85 inline-flex h-10 items-center rounded-full px-5 text-sm font-semibold text-white transition"
        >
          Download for Mac
        </Link>
      </aside>
    </main>
  );
}
