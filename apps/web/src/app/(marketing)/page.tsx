import type { Metadata } from "next";
import Link from "next/link";
import { ConnectorMarquee } from "@/components/marketing/ConnectorMarquee";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { HeroGlyphs } from "@/components/marketing/HeroGlyphs";
import { NotchBento } from "@/components/marketing/NotchBento";
import { NotchShowcase } from "@/components/marketing/NotchShowcase";
import { PricingSection } from "@/components/marketing/PricingSection";
import { SecuritySection } from "@/components/marketing/SecuritySection";
import { Section } from "@/components/marketing/primitives";
import { SiliconChip } from "@/components/marketing/SiliconChip";
import { AppleMark, ArrowRight } from "@/components/marketing/icons";
import { connectable } from "@notch/integrations";
import { JsonLd } from "@/components/JsonLd";
import { graph, organizationJsonLd, softwareApplicationJsonLd, websiteJsonLd } from "@/lib/jsonld";
import { LLM_ALTERNATES, absoluteUrl } from "@/lib/site";

const ASSETS = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

/**
 * The home page's own canonical, not the root layout's.
 *
 * `alternates` is inherited by every child route, so a canonical set once in
 * the layout would have `/privacy` and every blog post all claiming to be
 * `/` — the one mistake in this file that could de-index the whole site.
 */
export const metadata: Metadata = {
  alternates: { canonical: "/", types: LLM_ALTERNATES },
  openGraph: { url: absoluteUrl("/") },
};

/**
 * Organisation, site and product, as one graph.
 *
 * The `SoftwareApplication` is what earns the price, the platform and the
 * rating slots in a search result rather than a bare blue link. Its offers
 * come off `PLANS` inside the builder, so the markup cannot quote a price
 * the checkout no longer charges.
 */
const JSON_LD = graph(organizationJsonLd(), websiteJsonLd(), softwareApplicationJsonLd());

/**
 * The version under the download button, from the same manifest the button
 * redirects to. Absent rather than wrong when the mirror cannot be reached:
 * a page that says v0.3 while the button hands out v0.4 is the one thing
 * this line must never do.
 */
async function latestVersion(): Promise<string | null> {
  try {
    const response = await fetch(`${ASSETS}/desktop/latest.json`, { next: { revalidate: 300 } });
    if (!response.ok) return null;
    const body = (await response.json()) as { version?: unknown };
    return typeof body.version === "string" ? body.version : null;
  } catch {
    return null;
  }
}

export default async function Home() {
  const version = await latestVersion();

  return (
    <main className="relative">
      <JsonLd data={JSON_LD} />

      {/* Hero */}
      <section className="relative isolate px-6 pb-16 pt-32 sm:pt-40">
        {/* The headline block is the positioning context for the scattered
            marks, so they are placed against the text they have to miss
            rather than against the whole section, which grows by the height
            of the showcase below. */}
        <div className="relative mx-auto max-w-3xl">
          <HeroGlyphs />

          <div className="relative flex flex-col items-center text-center">
            <Link
              href="#integrations"
              className="border-ink/10 text-ink/70 hover:text-ink group flex items-center gap-2 rounded-full border bg-white/70 py-1 pl-1 pr-3 text-[13px] shadow-[0_6px_20px_-12px_rgba(11,10,14,0.4)] backdrop-blur-sm transition hover:bg-white"
            >
              <span className="brand-gradient rounded-full px-2.5 py-0.5 text-[11px] font-semibold text-white">
                New
              </span>
              Polar, Paddle and RevenueCat
              <ArrowRight className="h-3.5 w-3.5 transition group-hover:translate-x-0.5" />
            </Link>

            <h1 className="mt-8 text-balance text-[3rem] font-bold leading-[0.95] tracking-[-0.035em] sm:text-[4.75rem]">
              Put your <ChartGlyph /> metrics
              <br />
              in the notch <NotchGlyph />
            </h1>

            <p className="text-ink/60 mt-7 max-w-lg text-pretty text-lg leading-relaxed">
              Notch Metrics puts your revenue, MRR and subscribers in your MacBook&rsquo;s notch.
              Look up, and the number is already there.
            </p>

            <div className="mt-9 flex flex-col items-center gap-4">
              <div className="flex flex-wrap items-center justify-center gap-3">
                <DownloadButton size="lg" />
                <Link
                  href="#integrations"
                  className="border-ink/10 text-ink hover:border-ink/20 inline-flex h-12 items-center rounded-full border bg-white px-6 text-[15px] font-semibold shadow-[0_8px_24px_-14px_rgba(11,10,14,0.5)] transition"
                >
                  See what it shows
                </Link>
              </div>
              <p className="text-ink/40 font-mono text-[11px] tracking-wide">
                {version ? `v${version} · ` : ""}Apple silicon · macOS 14+ · 7-day free trial
              </p>
            </div>
          </div>
        </div>

        <div className="mx-auto mt-16 max-w-5xl sm:mt-20">
          <NotchShowcase />
        </div>
      </section>

      <NotchBento />

      {/* What the notch can hold */}
      <Section
        id="integrations"
        title={<>Payments, analytics and code, side by side</>}
        lede={`Stripe beside Plausible beside GitHub, on the same strip of glass. ${connectable().length} sources today, and a new one arrives without an app update.`}
      >
        <ConnectorMarquee />
      </Section>

      <SecuritySection />

      <PricingSection />

      {/* Designed for the Mac. The one dark card on a light page: it holds
          the silicon chip, which is drawn as a chip and reads as a sticker
          on paper. */}
      <section className="mx-auto max-w-5xl px-6 pt-28">
        <div className="bg-ink overflow-hidden rounded-[32px] shadow-[0_30px_80px_-40px_rgba(11,10,14,0.5)]">
          <div className="grid items-center gap-10 px-8 py-12 sm:px-12 lg:grid-cols-[1.1fr_1fr] lg:gap-6 lg:py-16">
            <div className="text-center lg:text-left">
              <p className="eyebrow !text-white/40">Built for macOS 14 and later</p>
              <h2 className="mt-2 text-5xl text-white sm:text-6xl">
                Native to <span className="accent">Mac</span>
              </h2>
              <p className="mx-auto mt-5 max-w-md text-pretty text-white/60 lg:mx-0">
                Built for Apple silicon. It opens the moment you look up, keeps out of your way
                while you work, and is light on memory and on your battery.
              </p>
              <div className="mt-8 flex justify-center lg:justify-start">
                <Link
                  href="/download"
                  className="text-ink inline-flex h-12 items-center gap-2 rounded-full bg-white px-6 text-[15px] font-semibold transition hover:bg-white/90"
                >
                  <AppleMark className="h-4 w-4" />
                  Download for Mac
                </Link>
              </div>
            </div>
            <div className="flex justify-center lg:justify-end">
              <SiliconChip />
            </div>
          </div>
        </div>
      </section>

      {/* The closing line the whole page is for. */}
      <section className="relative isolate mx-auto max-w-3xl px-6 pb-8 pt-32 text-center">
        <h2 className="text-balance text-[2.75rem] font-bold leading-[0.98] tracking-[-0.03em] sm:text-6xl">
          Never miss
          <br />a <span className="accent">number</span>.
        </h2>
        <p className="text-ink/60 mx-auto mt-6 max-w-md text-pretty text-lg leading-relaxed">
          Seven days free, no card. Connect a source on the web, and every Mac you own picks it up.
        </p>
        <div className="mt-9 flex flex-col items-center gap-4">
          <DownloadButton size="lg" />
          <p className="text-ink/40 font-mono text-[11px] tracking-wide">
            Apple silicon · macOS 14 or later
          </p>
        </div>
      </section>
    </main>
  );
}

/**
 * The two drawings set into the headline.
 *
 * Drawn rather than typed as emoji: an emoji is a different face at a
 * different weight on every machine, and on a Mac it would arrive full
 * colour in the middle of a black headline. These are sized in `em`, so they
 * ride the type down to the mobile size with it.
 */
function ChartGlyph() {
  return (
    <span className="bg-ink inline-flex h-[0.88em] w-[0.88em] translate-y-[0.04em] -rotate-6 items-center justify-center rounded-[0.24em] align-middle">
      {/* The file, not the inline path: the mark's own colours are a
          gradient defined inside it, and this is the one place on the page
          that wants them rather than a flat fill. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/logo.svg" alt="" className="h-[0.58em] w-[0.58em]" />
      <span className="sr-only">(the Notch Metrics mark)</span>
    </span>
  );
}

/**
 * The top of a MacBook display with the notch in it: black glass, a light
 * desktop, and the notch hanging into it. The light screen is what makes the
 * shape a notch; drawn as a black tab alone it read as a dash.
 */
function NotchGlyph() {
  return (
    <span className="bg-ink inline-block h-[0.72em] w-[1.3em] translate-y-[-0.04em] rounded-[0.2em] p-[0.07em] align-middle">
      <span className="relative block h-full w-full overflow-hidden rounded-[0.13em] bg-[#f1ecf5]">
        <span className="bg-ink absolute left-1/2 top-0 h-[36%] w-[40%] -translate-x-1/2 rounded-b-[0.07em]" />
      </span>
      <span className="sr-only">(the notch)</span>
    </span>
  );
}
