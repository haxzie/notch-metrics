import type { Metadata } from "next";
import { readChangelog } from "@/lib/changelog";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { absoluteUrl } from "@/lib/site";

/**
 * Where a release note lives.
 *
 * The repository is private, so the manifest's `notes` URL and the app's
 * Updates pane both point here. `force-static` because `readChangelog` uses
 * `node:fs`, which does not exist on the Worker this deploys to: the read has
 * to happen during `next build` or the route builds fine and 500s in
 * production.
 */
export const dynamic = "force-static";

export const metadata: Metadata = {
  title: "What's new",
  description: "Every released version of Notch Metrics, and what changed in it.",
  alternates: { canonical: "/changelog" },
  openGraph: { url: absoluteUrl("/changelog"), title: "What's new" },
};

export default function Changelog() {
  const releases = readChangelog();

  return (
    <main className="mx-auto max-w-2xl px-6 pb-24 pt-36">
      <h1 className="text-4xl font-semibold tracking-tight">What&rsquo;s new</h1>
      <p className="text-ink/60 mt-4 text-pretty">
        Every released version of Notch Metrics, newest first. Updates install from inside the app.
      </p>
      <DownloadButton className="mt-8" />

      {releases.length === 0 ? (
        <p className="text-ink/50 mt-16 text-sm">The first version has not shipped yet.</p>
      ) : (
        <div className="mt-16 space-y-16">
          {releases.map((release) => (
            <section key={release.id} id={release.id} className="scroll-mt-28">
              <h2 className="text-ink/40 font-mono text-[13px] tracking-wide">
                Version {release.version}
              </h2>
              <div className="prose mt-4" dangerouslySetInnerHTML={{ __html: release.html }} />
            </section>
          ))}
        </div>
      )}
    </main>
  );
}
