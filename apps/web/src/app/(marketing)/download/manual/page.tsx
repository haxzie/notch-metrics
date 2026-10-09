import type { Metadata } from "next";
import Link from "next/link";

const ASSETS = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

export const metadata: Metadata = { title: "Download" };

/**
 * The fallback when `latest.json` cannot be read.
 *
 * Exists so the download button is never dead: a release manifest that is
 * briefly unreachable should not make the product look unshipped.
 */
export default function ManualDownload() {
  return (
    <main className="relative isolate mx-auto flex max-w-xl flex-col items-center px-6 pb-16 pt-36 text-center">
      <div className="hero-glow" />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/brand/app-icon.png"
        alt=""
        width={72}
        height={72}
        className="rounded-[18px] ring-1 ring-white/15"
      />
      <h1 className="mt-8 text-4xl font-semibold tracking-tight">Download Notch Metrics</h1>
      <p className="mt-4 text-pretty text-white/60">
        We could not reach the release manifest just now. This is usually brief. The disk images are
        served from <code className="font-mono text-[13px] text-white/80">{ASSETS}</code>, so trying
        again in a moment normally works.
      </p>
      <Link
        href="/download"
        className="mt-8 inline-flex h-11 items-center rounded-full bg-white px-6 text-sm font-semibold text-black transition hover:bg-white/90"
      >
        Try the download again
      </Link>
      <p className="mt-4 font-mono text-[11px] tracking-wide text-white/40">
        Apple silicon · macOS 14 or later
      </p>
    </main>
  );
}
