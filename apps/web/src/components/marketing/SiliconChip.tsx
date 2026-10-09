/**
 * A chip on its substrate, drawn in CSS: hatched plate, four screws, a
 * chamfered corner, and a holographic die with the logo embossed in it.
 *
 * It stands in for "native, built for Apple silicon" without borrowing
 * Apple's own artwork. Everything is gradients and one SVG path, so it is
 * crisp at any size and costs no image request.
 */
export function SiliconChip() {
  return (
    <div className="relative mx-auto h-[280px] w-[280px] sm:h-[320px] sm:w-[320px]">
      {/* Guide lines running off the plate, as on a layout drawing. */}
      <span aria-hidden className="absolute -inset-y-40 left-0 w-px bg-white/[0.06]" />
      <span aria-hidden className="absolute -inset-y-40 right-0 w-px bg-white/[0.06]" />
      <span aria-hidden className="absolute -inset-x-[60vw] top-0 h-px bg-white/[0.06]" />
      <span aria-hidden className="absolute -inset-x-[60vw] bottom-0 h-px bg-white/[0.06]" />

      {/* The plate. */}
      <div
        className="absolute inset-0 border border-white/[0.08] bg-[#1a191e]"
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

      {/* The die. */}
      <div
        className="absolute inset-[16%] overflow-hidden rounded-[12px] shadow-[0_0_0_1px_rgba(255,255,255,0.12),0_30px_60px_-20px_rgba(120,140,255,0.45),inset_0_1px_0_rgba(255,255,255,0.25)]"
        style={{
          background: [
            // The light streak, sharp in the middle and soft at the edges.
            "linear-gradient(135deg, transparent 34%, rgba(255,255,255,0.35) 44%, rgba(255,255,255,0.95) 49%, rgba(255,255,255,0.35) 54%, transparent 64%)",
            // The iridescence.
            "linear-gradient(135deg, rgba(60,80,220,0.75) 0%, rgba(90,200,140,0.7) 40%, rgba(240,230,120,0.55) 55%, rgba(230,90,200,0.75) 75%, rgba(60,80,220,0.8) 100%)",
            "linear-gradient(180deg, #161a26, #1b2420)",
          ].join(","),
        }}
      >
        <span className="absolute right-3 top-2.5 font-mono text-[10px] tracking-[0.2em] text-black/50">
          № 0001
        </span>
        <span className="absolute bottom-2.5 left-3 font-mono text-[10px] tracking-[0.2em] text-black/50">
          NOTCH
        </span>
        <span className="absolute bottom-2.5 right-3 font-mono text-[10px] tracking-[0.2em] text-black/50">
          ARM64
        </span>

        {/* The logo, embossed. */}
        <svg
          viewBox="0 0 512 512"
          className="absolute left-1/2 top-1/2 h-[64%] w-[64%] -translate-x-1/2 -translate-y-1/2"
          aria-hidden
        >
          <defs>
            <linearGradient id="chip-metal" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stopColor="#ffffff" />
              <stop offset="0.5" stopColor="#d9d9df" />
              <stop offset="1" stopColor="#9b9ba6" />
            </linearGradient>
            <filter id="chip-emboss" x="-20%" y="-20%" width="140%" height="140%">
              <feDropShadow
                dx="0"
                dy="2"
                stdDeviation="1.5"
                floodColor="#000"
                floodOpacity="0.45"
              />
              <feDropShadow
                dx="0"
                dy="-1"
                stdDeviation="0.5"
                floodColor="#fff"
                floodOpacity="0.5"
              />
            </filter>
          </defs>
          <path
            filter="url(#chip-emboss)"
            fill="url(#chip-metal)"
            d="M451.279 149C459.024 149 466.451 152.076 471.927 157.553C477.404 163.029 480.48 170.457 480.48 178.201V275.538C480.48 283.283 477.404 290.71 471.927 296.187C466.451 301.663 459.024 304.739 451.279 304.739C443.534 304.739 436.107 301.663 430.631 296.187C425.154 290.71 422.078 283.283 422.078 275.538V248.712L343.702 327.049C330.925 339.816 313.602 346.988 295.54 346.988C277.477 346.988 260.153 339.816 247.377 327.049L185.626 265.298C184.722 264.392 183.648 263.672 182.465 263.182C181.283 262.691 180.015 262.439 178.735 262.438C177.455 262.438 176.186 262.691 175.004 263.182C173.821 263.672 172.747 264.392 171.843 265.298L82.5651 354.576C79.8919 357.445 76.6683 359.746 73.0866 361.342C69.5046 362.938 65.6373 363.796 61.7164 363.865C57.7957 363.934 53.9012 363.214 50.2653 361.745C46.6293 360.276 43.3262 358.09 40.5534 355.317C37.7805 352.545 35.5943 349.241 34.1256 345.605C32.657 341.97 31.9354 338.075 32.0045 334.154C32.0737 330.233 32.932 326.366 34.528 322.784C36.124 319.202 38.4256 315.978 41.2946 313.305L130.572 224.027C143.349 211.26 160.673 204.088 178.735 204.088C196.797 204.088 214.121 211.26 226.897 224.027L288.648 285.778C289.552 286.685 290.627 287.404 291.809 287.895C292.992 288.385 294.26 288.638 295.54 288.638C296.82 288.638 298.088 288.385 299.27 287.895C300.453 287.404 301.527 286.685 302.431 285.778L380.807 207.402H353.942C337.823 207.402 324.741 194.32 324.741 178.201C324.741 170.457 327.817 163.029 333.294 157.553C338.77 152.076 346.197 149 353.942 149H451.279Z"
          />
        </svg>
      </div>
    </div>
  );
}

function Screw({ className }: { className: string }) {
  return (
    <span
      aria-hidden
      className={`absolute h-5 w-5 rounded-full shadow-[inset_0_1px_1px_rgba(255,255,255,0.25),inset_0_-1px_2px_rgba(0,0,0,0.8),0_1px_2px_rgba(0,0,0,0.6)] ${className}`}
      style={{ background: "radial-gradient(circle at 35% 30%, #4a4850, #1d1c21 70%)" }}
    >
      <span className="absolute left-1/2 top-1/2 h-[2px] w-3 -translate-x-1/2 -translate-y-1/2 rotate-45 rounded bg-black/80" />
      <span className="absolute left-1/2 top-1/2 h-[2px] w-3 -translate-x-1/2 -translate-y-1/2 -rotate-45 rounded bg-black/80" />
    </span>
  );
}
