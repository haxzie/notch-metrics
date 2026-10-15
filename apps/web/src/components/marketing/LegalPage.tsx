import type { ReactNode } from "react";

/**
 * The frame both legal pages share: one column of measured prose, a date
 * that says when the text last changed, and headings a reader can skim to.
 *
 * Plain elements with explicit classes rather than a typography plugin —
 * the site has none, and two pages do not justify adding one.
 */
export function LegalPage({
  title,
  summary,
  updated,
  children,
}: {
  title: string;
  summary: string;
  /** ISO date. Shown, and used for the `<time>` so a crawler reads it too. */
  updated: string;
  children: ReactNode;
}) {
  const shown = new Date(`${updated}T00:00:00Z`).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });

  return (
    <main className="relative isolate mx-auto max-w-2xl px-6 pb-16 pt-36">
      <h1 className="text-4xl font-semibold tracking-tight">{title}</h1>
      <p className="text-ink/60 mt-4 text-pretty text-lg">{summary}</p>
      <p className="text-ink/40 mt-3 font-mono text-[11px] tracking-wide">
        Last updated <time dateTime={updated}>{shown}</time>
      </p>
      <div className="legal mt-12 flex flex-col gap-10">{children}</div>
    </main>
  );
}

export function LegalSection({ title, children }: { title: string; children: ReactNode }) {
  const id = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
  return (
    <section id={id} className="scroll-mt-28">
      <h2 className="text-xl font-semibold tracking-tight">
        <a href={`#${id}`} className="hover:text-ink/80">
          {title}
        </a>
      </h2>
      <div className="text-ink/65 [&_a]:text-ink [&_a]:decoration-ink/30 [&_strong]:text-ink/90 mt-3 flex flex-col gap-3 text-[15px] leading-relaxed [&_a]:underline [&_a]:underline-offset-2 hover:[&_a]:decoration-white [&_li]:pl-1 [&_strong]:font-medium [&_ul]:flex [&_ul]:list-disc [&_ul]:flex-col [&_ul]:gap-1.5 [&_ul]:pl-5">
        {children}
      </div>
    </section>
  );
}
