import { HoloFoil } from "./HoloFoil";
import { NotchMark } from "./icons";

/**
 * A chip on its substrate, drawn in CSS: hatched plate, four screws, a
 * chamfered corner, and a holographic die with the logo embossed in it.
 *
 * It stands in for "native, built for Apple silicon" without borrowing
 * Apple's own artwork. The plate and screws are flat; the die is the one
 * place with a finish on it, because a hologram is the thing the eye goes
 * to on a sticker and this is the page's full stop.
 */
export function SiliconChip() {
  return (
    <div className="relative h-[260px] w-[260px] sm:h-[300px] sm:w-[300px]">
      {/* Guide lines running off the plate, as on a layout drawing. */}
      <span aria-hidden className="bg-ink/[0.06] absolute -inset-y-24 left-0 w-px" />
      <span aria-hidden className="bg-ink/[0.06] absolute -inset-y-24 right-0 w-px" />
      <span aria-hidden className="bg-ink/[0.06] absolute -inset-x-20 top-0 h-px" />
      <span aria-hidden className="bg-ink/[0.06] absolute -inset-x-20 bottom-0 h-px" />

      {/* The plate. */}
      <div
        className="border-ink/[0.08] absolute inset-0 border bg-[#17161b]"
        style={{
          clipPath: "polygon(0 0, calc(100% - 44px) 0, 100% 44px, 100% 100%, 0 100%)",
          backgroundImage:
            "repeating-linear-gradient(135deg, rgba(255,255,255,0.055) 0 1px, transparent 1px 11px)",
        }}
      />
      {/* The semicircular index notch on the right edge. */}
      <span
        aria-hidden
        className="absolute right-0 top-1/2 h-9 w-[18px] -translate-y-1/2 rounded-l-full bg-[#0b0a0e] shadow-[inset_2px_0_4px_rgba(0,0,0,0.6)]"
      />

      <Screw className="left-4 top-4" />
      <Screw className="bottom-4 left-4" />
      <Screw className="bottom-4 right-4" />

      {/* The die, finished like a holographic sticker. */}
      <div className="absolute inset-[16%] overflow-hidden rounded-[12px] bg-[#101014] shadow-[0_0_0_1px_rgba(255,255,255,0.12),0_18px_40px_-16px_rgba(11,10,14,0.8)]">
        {/* The foil. The canvas draws over this once WebGL is up; the
            gradient underneath is what the die looks like if it never is. */}
        <span
          aria-hidden
          className="absolute inset-0"
          style={{
            background:
              "linear-gradient(135deg, rgba(60,80,220,0.55) 0%, rgba(90,200,140,0.5) 35%, rgba(240,230,120,0.4) 55%, rgba(230,90,200,0.55) 80%, rgba(60,80,220,0.5) 100%)",
          }}
        />
        <HoloFoil />

        <span className="absolute right-3 top-2.5 z-10 font-mono text-[10px] tracking-[0.2em] text-white/35">
          № 0001
        </span>
        <span className="absolute bottom-2.5 left-3 z-10 font-mono text-[10px] tracking-[0.2em] text-white/35">
          NOTCH
        </span>
        <span className="absolute bottom-2.5 right-3 z-10 font-mono text-[10px] tracking-[0.2em] text-white/35">
          ARM64
        </span>

        {/* The mark, embossed into the foil. White, because amber on a
            surface carrying every other colour is the one that disappears. */}
        <NotchMark className="absolute left-1/2 top-1/2 z-10 h-[64%] w-[64%] -translate-x-1/2 -translate-y-1/2 text-white drop-shadow-[0_2px_3px_rgba(11,10,14,0.55)]" />
      </div>
    </div>
  );
}

function Screw({ className }: { className: string }) {
  return (
    <span
      aria-hidden
      className={`absolute h-5 w-5 rounded-full bg-[#2b2a31] ring-1 ring-white/10 ${className}`}
    >
      <span className="absolute left-1/2 top-1/2 h-[2px] w-3 -translate-x-1/2 -translate-y-1/2 rotate-45 rounded bg-black/80" />
      <span className="absolute left-1/2 top-1/2 h-[2px] w-3 -translate-x-1/2 -translate-y-1/2 -rotate-45 rounded bg-black/80" />
    </span>
  );
}
