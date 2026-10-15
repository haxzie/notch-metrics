import type { Metadata } from "next";
import Link from "next/link";

const API = process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com";

export const metadata: Metadata = {
  title: "Download",
  alternates: { canonical: "/download/manual" },
};

/**
 * The fallback when the update feed cannot be read.
 *
 * Exists so the download button is never dead: a release manifest that is
 * briefly unreachable should not make the product look unshipped. The direct
 * link goes to the Worker rather than to the bucket, so a release withheld by
 * `PINNED_VERSION` stays withheld here too — a bucket URL on this page would
 * be the one route around a rollback.
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
        The release feed did not answer just now. This is usually brief. Trying again in a moment
        normally works.
      </p>
      <Link
        href="/download"
        className="bg-ink hover:bg-ink/85 mt-8 inline-flex h-11 items-center rounded-full px-6 text-sm font-semibold text-white transition"
      >
        Try the download again
      </Link>
      <a
        href={`${API}/v1/updates/download`}
        className="text-ink/60 hover:text-ink mt-4 text-sm underline underline-offset-4 transition"
      >
        Or take the disk image straight from the release feed
      </a>
      <p className="text-ink/40 mt-6 font-mono text-[11px] tracking-wide">
        Apple silicon · macOS 14 or later
      </p>
    </main>
  );
}
