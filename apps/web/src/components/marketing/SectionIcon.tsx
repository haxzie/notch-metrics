/**
 * The glowing tile that opens a section: brand gradient, a white glyph, and
 * a wash of the same colours behind it so the section has a focal point
 * before the headline.
 */
export function SectionIcon({ children }: { children: React.ReactNode }) {
  return (
    <div className="icon-glow mx-auto flex h-16 w-16 items-center justify-center rounded-[20px] border border-white/15 bg-white/[0.06] p-[3px] shadow-[0_12px_40px_-10px_rgba(216,25,194,0.5)]">
      <div className="brand-gradient flex h-full w-full items-center justify-center rounded-[17px] text-white [&>svg]:h-7 [&>svg]:w-7">
        {children}
      </div>
    </div>
  );
}
