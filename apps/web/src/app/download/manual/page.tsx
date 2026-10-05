import Link from "next/link";

const ASSETS = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

/**
 * The fallback when `latest.json` cannot be read.
 *
 * Exists so the download button is never dead: a release manifest that is
 * briefly unreachable should not make the product look unshipped.
 */
export default function ManualDownload() {
  return (
    <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-24">
      <h1 className="text-3xl font-semibold tracking-tight">Download Notch Metrics</h1>
      <p className="text-white/60">
        We could not reach the release manifest just now. Every release is also listed on GitHub,
        and the disk images are served directly from <code className="text-white/80">{ASSETS}</code>
        .
      </p>
      <Link
        href="https://github.com/haxzie/notch-metrics/releases"
        className="brand-gradient w-fit rounded-full px-5 py-2.5 text-sm font-semibold text-black"
      >
        All releases on GitHub
      </Link>
      <p className="text-sm text-white/40">Apple silicon, macOS 14 or later.</p>
    </main>
  );
}
