import type { Metadata } from "next";
import Link from "next/link";

const ASSETS = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

export const metadata: Metadata = {
  title: "Download",
  alternates: { canonical: "/download/manual" },
};

/**
 * The fallback when `latest.json` cannot be read.
 *
 * Exists so the download button is never dead: a release manifest that is
 * briefly unreachable should not make the product look unshipped.
 */
export default function ManualDownload() {
  return (
    <main className="relative isolate mx-auto flex max-w-xl flex-col items-center px-6 pb-16 pt-36 text-center">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/brand/app-icon.png"
        alt=""
        width={72}
        height={72}
        className="ring-ink/15 rounded-[18px] ring-1"
      />
      <h1 className="mt-8 text-4xl font-semibold tracking-tight">Download Notch Metrics</h1>
      <p className="text-ink/60 mt-4 text-pretty">
        We could not reach the release manifest just now. This is usually brief. The disk images are
        served from <code className="text-ink/80 font-mono text-[13px]">{ASSETS}</code>, so trying
        again in a moment normally works.
      </p>
      <Link
        href="/download"
        className="bg-ink hover:bg-ink/85 mt-8 inline-flex h-11 items-center rounded-full px-6 text-sm font-semibold text-white transition"
      >
        Try the download again
      </Link>
      <p className="text-ink/40 mt-4 font-mono text-[11px] tracking-wide">
        Apple silicon · macOS 14 or later
      </p>
    </main>
  );
}
