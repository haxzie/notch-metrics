import { SectionIcon } from "@/components/marketing/SectionIcon";

/**
 * The landing page's layout pieces, shared with `/sources` and `/library`.
 *
 * Lifted out of `(marketing)/page.tsx`, where they were local functions. The
 * generated pages need the same section rhythm and the same card, and a
 * second copy of this Tailwind is a second place the spacing drifts.
 */
export function Section({
  id,
  icon,
  title,
  lede,
  children,
}: {
  id?: string;
  icon: React.ReactNode;
  title: React.ReactNode;
  lede: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="mx-auto max-w-5xl scroll-mt-28 px-6 pt-28">
      <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <SectionIcon>{icon}</SectionIcon>
        <h2 className="mt-8 text-balance text-4xl font-semibold leading-[1.08] tracking-tight sm:text-[2.75rem]">
          {title}
        </h2>
        <p className="mt-5 max-w-xl text-pretty text-[17px] leading-relaxed text-white/55">
          {lede}
        </p>
      </div>
      <div className="mt-12">{children}</div>
    </section>
  );
}

export function Pillar({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <span className="flex h-11 w-11 items-center justify-center rounded-xl border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <p className="text-[15px] leading-snug text-white/80">{children}</p>
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
      <span className="flex h-10 w-10 items-center justify-center rounded-xl border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-pretty text-sm leading-relaxed text-white/50">{children}</p>
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
      <span className="flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-[18px] [&>svg]:w-[18px]">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-pretty text-sm leading-relaxed text-white/50">{children}</p>
    </div>
  );
}
