import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ConnectorMark } from "@/components/ConnectorMark";
import { JsonLd } from "@/components/JsonLd";
import { Ticks } from "@/components/Ticks";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { FaqSection } from "@/lib/faq";
import { breadcrumbJsonLd, definedTermJsonLd, faqPageJsonLd, graph } from "@/lib/jsonld";
import { absoluteUrl } from "@/lib/site";
import { metricCopy } from "@/lib/source-copy";
import {
  generatedMetricFaq,
  granularityPhrase,
  metricBySlug,
  metricPages,
  metricSlug,
  plain,
  providersReporting,
  statusNote,
  unitDescription,
} from "@/lib/sources";

// Sidecars are read with `node:fs` — see the note in src/lib/collection.ts.
export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { provider: string; metric: string }[] {
  return metricPages().map(({ manifest, metric }) => ({
    provider: manifest.id,
    metric: metricSlug(metric.id),
  }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ provider: string; metric: string }>;
}): Promise<Metadata> {
  const { provider, metric } = await params;
  const page = metricBySlug(provider, metric);
  if (!page) return {};

  const title = `${page.manifest.name} ${page.metric.label.toLowerCase()}`;

  return {
    // Built from the descriptor's own label, never from the metric id. The
    // same id is "Revenue" on Stripe, "Sales" on Shopify and "Estimated
    // revenue" on YouTube, and a title built from `revenue` would say the
    // wrong thing on two of the three.
    title: `${title} in the MacBook notch`,
    // The methodology sentence is the honest description and it is different
    // on every one of these pages, which is the point.
    description: plain(page.metric.methodology).slice(0, 158),
    alternates: { canonical: page.path },
    keywords: [page.manifest.name, page.metric.label, ...(page.metric.keywords ?? [])],
    openGraph: { url: absoluteUrl(page.path), title: `${title} in the MacBook notch` },
  };
}

export default async function MetricPage({
  params,
}: {
  params: Promise<{ provider: string; metric: string }>;
}) {
  const { provider, metric: metricParam } = await params;
  const page = metricBySlug(provider, metricParam);
  if (!page) notFound();

  const { manifest, metric, path, isList } = page;
  const copy = metricCopy(manifest.id, metricParam);
  const faq = copy?.faq ?? generatedMetricFaq(manifest, metric);
  const others = providersReporting(metric.id, manifest.id);
  const note = statusNote(manifest.status);
  const title = `${manifest.name} ${metric.label.toLowerCase()}`;

  const jsonLd = graph(
    definedTermJsonLd({
      name: `${manifest.name} ${metric.label}`,
      description: metric.methodology,
      path,
      setName: `${manifest.name} metrics`,
      setPath: `/sources/${manifest.id}`,
    }),
    faqPageJsonLd(faq, path),
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Sources", path: "/sources" },
        { name: manifest.name, path: `/sources/${manifest.id}` },
        { name: metric.label, path },
      ],
      path,
    ),
  );

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />
      <div className="hero-glow" />

      <nav aria-label="Breadcrumb" className="font-mono text-[11px] tracking-wide text-white/40">
        <ol className="flex flex-wrap items-center gap-2">
          <li>
            <Link href="/" className="transition hover:text-white">
              Home
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href="/sources" className="transition hover:text-white">
              Sources
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href={`/sources/${manifest.id}`} className="transition hover:text-white">
              {manifest.name}
            </Link>
          </li>
        </ol>
      </nav>

      <header className="mt-6 flex items-start gap-5">
        <ConnectorMark
          id={manifest.id}
          name={manifest.name}
          accentColor={manifest.accentColor}
          size={56}
          shape="squircle"
        />
        <div>
          <h1 className="text-balance text-[2rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.5rem]">
            {title} in the MacBook notch
          </h1>
          {copy?.lede && (
            <p className="mt-4 text-pretty text-[17px] leading-relaxed text-white/60">
              {copy.lede}
            </p>
          )}
        </div>
      </header>

      {copy?.html && (
        <div className="prose mt-10" dangerouslySetInnerHTML={{ __html: copy.html }} />
      )}

      <section className="mt-14">
        <h2 className="text-xl font-semibold tracking-tight">What {title} means, exactly</h2>
        {/* The methodology sentence, verbatim. It is required on every
            descriptor, it is specific, and it is the one thing on this page
            that nobody else on the web has written. Paraphrasing it would
            cost the page the only sentence worth ranking. */}
        <p className="mt-4 text-[17px] leading-relaxed text-white/70">
          <Ticks>{metric.methodology}</Ticks>
        </p>
        <p className="mt-4 text-[15px] leading-relaxed text-white/55">
          {unitDescription(metric.unit)}
        </p>
      </section>

      <section className="mt-14">
        <h2 className="text-xl font-semibold tracking-tight">How the widget behaves</h2>
        <dl className="mt-6 grid gap-x-8 gap-y-5 sm:grid-cols-2">
          <div>
            <dt className="eyebrow">Buckets</dt>
            <dd className="mt-1.5 text-[15px] text-white/70">{granularityPhrase(metric)}</dd>
          </div>
          <div>
            <dt className="eyebrow">Shape</dt>
            <dd className="mt-1.5 text-[15px] text-white/70">
              {isList
                ? "A feed of the ten most recent rows, with their total as the headline"
                : metric.supportsSeries
                  ? "A figure with a sparkline"
                  : "A figure, with no sparkline"}
            </dd>
          </div>
          <div>
            <dt className="eyebrow">Against last period</dt>
            <dd className="mt-1.5 text-[15px] text-white/70">
              {metric.supportsCompare ? "Yes" : "No"}
            </dd>
          </div>
          <div>
            <dt className="eyebrow">Fetched from</dt>
            <dd className="mt-1.5 font-mono text-[13px] text-white/60">
              {manifest.allowedHosts.join(", ")}
            </dd>
          </div>
        </dl>

        {metric.params && metric.params.length > 0 && (
          <div className="mt-8">
            <h3 className="text-[15px] font-medium">What the widget asks you for</h3>
            <dl className="mt-3 flex flex-col gap-4">
              {metric.params.map((param) => (
                <div key={param.key}>
                  <dt className="text-[15px] text-white/90">{param.label}</dt>
                  {param.help && (
                    <dd className="mt-1 text-[15px] leading-relaxed text-white/55">{param.help}</dd>
                  )}
                  {param.placeholder && (
                    <dd className="mt-1 font-mono text-[12px] text-white/35">
                      {param.placeholder}
                    </dd>
                  )}
                </div>
              ))}
            </dl>
          </div>
        )}

        {note && <p className="mt-8 text-[15px] leading-relaxed text-white/55">{note}</p>}
      </section>

      {others.length > 0 && (
        <section className="mt-14">
          <h2 className="text-xl font-semibold tracking-tight">
            {metric.label} from other sources
          </h2>
          <p className="mt-4 text-[15px] leading-relaxed text-white/55">
            Notch Metrics reports {metric.label.toLowerCase()} from {others.length} other{" "}
            {others.length === 1 ? "source" : "sources"}. Each defines it its own way, so the
            widgets stay separate rather than being added together.
          </p>
          <ul className="mt-6 flex flex-col gap-3">
            {others.map((other) => (
              <li key={other.manifest.id}>
                <Link
                  href={other.path}
                  className="panel flex items-start gap-4 p-5 transition hover:bg-white/[0.05]"
                >
                  <ConnectorMark
                    id={other.manifest.id}
                    name={other.manifest.name}
                    accentColor={other.manifest.accentColor}
                    size={36}
                  />
                  <span className="flex flex-col gap-1.5">
                    <span className="text-[15px] font-medium">
                      {other.manifest.name} {other.metric.label.toLowerCase()}
                    </span>
                    <span className="text-sm leading-relaxed text-white/50">
                      <Ticks>{other.metric.methodology}</Ticks>
                    </span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <FaqSection entries={faq} />

      <aside className="panel mt-16 flex flex-col items-start gap-4 p-7">
        <h2 className="text-lg font-semibold tracking-tight">Put {title} in your notch</h2>
        <p className="text-[15px] leading-relaxed text-white/55">
          Connect {manifest.name} on the web, place the widget, and the number is there every time
          you glance up. Seven days of everything, with no card.
        </p>
        <DownloadButton />
      </aside>
    </main>
  );
}
