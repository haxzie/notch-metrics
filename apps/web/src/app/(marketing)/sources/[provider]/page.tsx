import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ConnectorMark } from "@/components/ConnectorMark";
import { JsonLd } from "@/components/JsonLd";
import { Ticks } from "@/components/Ticks";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { FaqSection } from "@/lib/faq";
import { breadcrumbJsonLd, faqPageJsonLd, graph, itemListJsonLd } from "@/lib/jsonld";
import { absoluteUrl } from "@/lib/site";
import { sourceCopy } from "@/lib/source-copy";
import {
  authPhrase,
  generatedSourceFaq,
  granularityPhrase,
  metricSlug,
  sourceBySlug,
  sourcePages,
  statusNote,
} from "@/lib/sources";

// Sidecars are read with `node:fs` — see the note in src/lib/collection.ts.
export const dynamic = "force-static";
// A provider that is not in the manifests, or is still `coming_soon`, 404s
// rather than being rendered on demand. On the Worker that would mean a
// runtime `fs` read that cannot succeed.
export const dynamicParams = false;

export function generateStaticParams(): { provider: string }[] {
  return sourcePages().map(({ manifest }) => ({ provider: manifest.id }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ provider: string }>;
}): Promise<Metadata> {
  const { provider } = await params;
  const manifest = sourceBySlug(provider);
  if (!manifest) return {};

  const path = `/sources/${manifest.id}`;

  return {
    title: `${manifest.name} in the MacBook notch`,
    description: manifest.tagline,
    alternates: { canonical: path },
    keywords: [manifest.name, ...(manifest.keywords ?? [])],
    openGraph: { url: absoluteUrl(path), title: `${manifest.name} in the MacBook notch` },
  };
}

export default async function SourcePage({ params }: { params: Promise<{ provider: string }> }) {
  const { provider } = await params;
  const manifest = sourceBySlug(provider);
  if (!manifest) notFound();

  const path = `/sources/${manifest.id}`;
  const copy = sourceCopy(manifest.id);
  const faq = copy?.faq ?? generatedSourceFaq(manifest);
  const note = statusNote(manifest.status);

  const jsonLd = graph(
    itemListJsonLd(
      manifest.metrics.map((metric) => ({
        name: metric.label,
        path: `${path}/${metricSlug(metric.id)}`,
      })),
      path,
    ),
    faqPageJsonLd(faq, path),
    breadcrumbJsonLd(
      [
        { name: "Home", path: "/" },
        { name: "Sources", path: "/sources" },
        { name: manifest.name, path },
      ],
      path,
    ),
  );

  return (
    <main className="relative isolate mx-auto max-w-3xl px-6 pb-16 pt-36">
      <JsonLd data={jsonLd} />

      <nav aria-label="Breadcrumb" className="text-ink/40 font-mono text-[11px] tracking-wide">
        <ol className="flex items-center gap-2">
          <li>
            <Link href="/" className="hover:text-ink transition">
              Home
            </Link>
          </li>
          <li aria-hidden>/</li>
          <li>
            <Link href="/sources" className="hover:text-ink transition">
              Sources
            </Link>
          </li>
        </ol>
      </nav>

      <header className="mt-6 flex items-start gap-5">
        <ConnectorMark
          id={manifest.id}
          name={manifest.name}
          accentColor={manifest.accentColor}
          size={64}
          shape="squircle"
        />
        <div>
          <h1 className="text-balance text-[2rem] font-semibold leading-[1.1] tracking-tight sm:text-[2.5rem]">
            {manifest.name} in the MacBook notch
          </h1>
          <p className="text-ink/60 mt-4 text-pretty text-[17px] leading-relaxed">
            {copy?.lede ?? manifest.tagline}
          </p>
        </div>
      </header>

      {note && (
        <p className="panel text-ink/55 mt-8 p-4 text-sm leading-relaxed">
          <span className="text-ink/40 font-mono text-[10px] uppercase tracking-wide">Beta</span>
          <br />
          {note}
        </p>
      )}

      {copy?.html && (
        <div className="prose mt-10" dangerouslySetInnerHTML={{ __html: copy.html }} />
      )}

      <section className="mt-14">
        <h2 className="text-xl font-semibold tracking-tight">
          The {manifest.metrics.length} numbers Notch Metrics reads from {manifest.name}
        </h2>
        <ul className="mt-6 flex flex-col gap-3">
          {manifest.metrics.map((metric) => (
            <li key={metric.id}>
              <Link
                href={`${path}/${metricSlug(metric.id)}`}
                className="panel hover:bg-ink/[0.05] flex flex-col gap-2 p-5 transition"
              >
                <span className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <span className="text-[15px] font-medium">{metric.label}</span>
                  <span className="text-ink/30 font-mono text-[11px] tracking-wide">
                    {granularityPhrase(metric)}
                    {metric.supportsSeries ? " · sparkline" : " · snapshot"}
                  </span>
                </span>
                <span className="text-ink/50 text-sm leading-relaxed">
                  <Ticks>{metric.methodology}</Ticks>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section className="mt-14">
        <h2 className="text-xl font-semibold tracking-tight">
          Connecting {manifest.name}, once, on the web
        </h2>
        <p className="text-ink/55 mt-4 text-[15px] leading-relaxed">{authPhrase(manifest)}</p>

        {manifest.authMode === "oauth2" && manifest.oauth ? (
          <>
            <p className="text-ink/55 mt-4 text-[15px] leading-relaxed">
              The prompt asks for exactly this much:
            </p>
            <ul className="mt-3 flex flex-col gap-2">
              {manifest.oauth.scopeSummary.map((scope) => (
                <li key={scope} className="text-ink/70 text-[15px] leading-relaxed">
                  <span aria-hidden className="text-ink/30 mr-2">
                    ·
                  </span>
                  {scope}
                </li>
              ))}
            </ul>
            {manifest.oauth.requiresSelection && manifest.oauth.selectionLabel && (
              <p className="text-ink/55 mt-4 text-[15px] leading-relaxed">
                After authorising, you pick {manifest.oauth.selectionLabel.toLowerCase()}.
              </p>
            )}
          </>
        ) : (
          <dl className="mt-5 flex flex-col gap-5">
            {manifest.fields.map((field) => (
              <div key={field.key}>
                <dt className="text-ink/90 text-[15px] font-medium">
                  {field.label}
                  {!field.required && (
                    <span className="text-ink/30 ml-2 font-mono text-[10px] uppercase tracking-wide">
                      optional
                    </span>
                  )}
                </dt>
                {field.help && (
                  <dd className="text-ink/55 mt-1.5 text-[15px] leading-relaxed">
                    <Ticks>{field.help}</Ticks>
                  </dd>
                )}
                {field.placeholder && (
                  <dd className="text-ink/35 mt-1.5 font-mono text-[12px]">{field.placeholder}</dd>
                )}
              </div>
            ))}
          </dl>
        )}

        <p className="text-ink/55 mt-6 text-[15px] leading-relaxed">
          Your {manifest.name} credential is encrypted with its own key, bound to your account and
          the provider. Our server calls {manifest.name} and hands your Mac a normalised number, so
          the Mac app never holds the credential. Remove the integration and the encrypted key is
          deleted with it.
        </p>
        <p className="text-ink/40 mt-4 text-[13px]">
          <a href={manifest.docsUrl} target="_blank" rel="noopener noreferrer">
            Where to find this in {manifest.name} ↗
          </a>
        </p>
      </section>

      {(manifest.keywords?.length ?? 0) > 0 && (
        <section className="mt-14">
          <h2 className="text-xl font-semibold tracking-tight">Also called</h2>
          <ul className="mt-4 flex flex-wrap gap-2">
            {manifest.keywords!.map((keyword) => (
              <li
                key={keyword}
                className="border-ink/10 bg-ink/[0.04] text-ink/50 rounded-full border px-3 py-1 font-mono text-[11px] tracking-wide"
              >
                {keyword}
              </li>
            ))}
          </ul>
        </section>
      )}

      <FaqSection entries={faq} />

      <aside className="panel mt-16 flex flex-col items-start gap-4 p-7">
        <h2 className="text-lg font-semibold tracking-tight">Put {manifest.name} in your notch</h2>
        <p className="text-ink/55 text-[15px] leading-relaxed">
          Seven days of everything, with no card. Apple silicon, macOS 14 and later.
        </p>
        <DownloadButton />
      </aside>
    </main>
  );
}
