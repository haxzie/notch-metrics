/**
 * The landing page's layout pieces, shared with `/sources` and `/library`.
 *
 * Lifted out of `(marketing)/page.tsx`, where they were local functions. The
 * generated pages need the same section rhythm and the same card, and a
 * second copy of this Tailwind is a second place the spacing drifts.
 */
export function Section({
  id,
  title,
  lede,
  children,
}: {
  id?: string;
  title: React.ReactNode;
  lede: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="mx-auto max-w-5xl scroll-mt-28 px-6 pt-28">
      <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <h2 className="text-balance text-[2.5rem] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[3.25rem]">
          {title}
        </h2>
        <p className="text-ink/55 mt-5 max-w-xl text-pretty text-[17px] leading-relaxed">{lede}</p>
      </div>
      <div className="mt-12">{children}</div>
    </section>
  );
}

export function Pillar({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <span className="border-ink/10 bg-ink/[0.05] text-ink/80 flex h-11 w-11 items-center justify-center rounded-xl border [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <p className="text-ink/80 text-[15px] leading-snug">{children}</p>
    </div>
  );
}

export function Feature({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-3 text-center">
      <span className="border-ink/10 bg-ink/[0.05] text-ink/80 flex h-10 w-10 items-center justify-center rounded-xl border [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-ink/50 text-pretty text-sm leading-relaxed">{children}</p>
    </div>
  );
}

export function SecurityCard({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="panel flex flex-col gap-3 p-6">
      <span className="border-ink/10 bg-ink/[0.05] text-ink/80 flex h-9 w-9 items-center justify-center rounded-lg border [&>svg]:h-[18px] [&>svg]:w-[18px]">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-ink/50 text-pretty text-sm leading-relaxed">{children}</p>
    </div>
  );
}
