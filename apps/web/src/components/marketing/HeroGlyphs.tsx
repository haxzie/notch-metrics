import { ConnectorMark } from "@/components/ConnectorMark";
import { catalogue } from "@notch/integrations";
import type { ProviderId } from "@notch/schemas";

/**
 * The field of connector marks scattered around the headline.
 *
 * Hand-placed, not generated. Every position is picked against the headline
 * and the buttons, so the layer is decoration that never lands on a word. A
 * loop over the catalogue would put a mark in the middle of the H1 the first
 * time somebody ships a fifteenth connector.
 *
 * Percentages, so the field stretches with the viewport and keeps its shape.
 * Values outside 0 to 100 are deliberate: the marks carry on past the text
 * column towards the edges of the screen, and `overflow-x: clip` on the body
 * is what stops the ones past the right edge adding a scrollbar.
 */
const MARKS: { id: ProviderId; left: number; top: number; size: number; tilt: number }[] = [
  // Left band.
  { id: "github", left: 12, top: 4, size: 46, tilt: 7 },
  { id: "stripe", left: 3, top: 20, size: 64, tilt: -9 },
  { id: "hubspot", left: 14, top: 36, size: 40, tilt: -7 },
  { id: "shopify", left: 9, top: 68, size: 56, tilt: -5 },
  { id: "plausible", left: 2, top: 86, size: 44, tilt: 10 },
  // Right band.
  { id: "lemonsqueezy", left: 85, top: 6, size: 48, tilt: -8 },
  { id: "paddle", left: 91, top: 24, size: 62, tilt: 8 },
  { id: "posthog", left: 94, top: 56, size: 50, tilt: -6 },
  { id: "revenuecat", left: 84, top: 74, size: 54, tilt: 7 },
  { id: "openai", left: 92, top: 90, size: 42, tilt: -10 },
];

const AMBER = "#ffc107";
const INK = "#1c1a21";

/** The bits between the marks. */
const CONFETTI: {
  shape: "spark" | "dot" | "tick" | "dash";
  left: number;
  top: number;
  colour: string;
  size: number;
  tilt: number;
}[] = [
  // Amber or ink, which is the whole palette. A third colour here is the
  // first step back to a hero that looks like a sticker sheet.
  { shape: "spark", left: 19, top: 14, colour: AMBER, size: 18, tilt: 0 },
  { shape: "tick", left: 8, top: 36, colour: INK, size: 22, tilt: 0 },
  { shape: "dot", left: 17, top: 58, colour: AMBER, size: 9, tilt: 0 },
  { shape: "dash", left: 15, top: 78, colour: INK, size: 26, tilt: 28 },
  { shape: "spark", left: 6, top: 96, colour: AMBER, size: 16, tilt: 0 },
  { shape: "dash", left: 80, top: 16, colour: AMBER, size: 24, tilt: -22 },
  { shape: "dot", left: 82, top: 36, colour: INK, size: 10, tilt: 0 },
  { shape: "tick", left: 80, top: 66, colour: AMBER, size: 20, tilt: 0 },
  { shape: "spark", left: 95, top: 4, colour: INK, size: 17, tilt: 0 },
];
/**
 * Two of the app's own tiles, floating with the marks.
 *
 * The icons alone say "your accounts"; the graph is what says what the app
 * does with them. They sit where two marks used to, so the field keeps its
 * balance.
 */
const CARDS: {
  kind: "spark" | "bars";
  left: number;
  top: number;
  tilt: number;
  label: string;
  value: string;
  delta: string;
  colour: string;
}[] = [
  {
    kind: "spark",
    left: 3,
    top: 48,
    tilt: -6,
    label: "MRR",
    value: "$12,480",
    delta: "+4.2% vs last month",
    colour: "#8f88ff",
  },
  {
    kind: "bars",
    left: 81,
    top: 38,
    tilt: 6,
    label: "Revenue · 7d",
    value: "$3,920",
    delta: "+11% vs last week",
    colour: "#c6f135",
  },
];

const SPARK = [30, 26, 28, 20, 22, 15, 17, 10, 12, 6, 8, 2];
const BARS = [42, 58, 51, 74, 66, 88, 97];

export function HeroGlyphs() {
  const manifests = new Map(
    catalogue()
      .flatMap((group) => group.connectors)
      .map((connector) => [connector.id, connector]),
  );

  return (
    <div
      aria-hidden
      /* Full-bleed, full-viewport rather than column-width: the marks are placed
         against the viewport, not against the 48rem text column they have to
         stay clear of. Below `xl` that column leaves no room either side, so
         the whole field is off rather than printed over the headline. */
      className="pointer-events-none absolute inset-y-0 left-1/2 hidden w-screen -translate-x-1/2 xl:block"
    >
      {CONFETTI.map((piece, i) => (
        <span
          key={`confetti-${i}`}
          className="hero-drift absolute"
          style={{
            left: `${piece.left}%`,
            top: `${piece.top}%`,
            // Every piece drifts on the same nine seconds. The offset is what
            // stops thirteen icons rising and falling as one object.
            animationDelay: `${(i * 0.73).toFixed(2)}s`,
            ["--tilt" as string]: `${piece.tilt}deg`,
          }}
        >
          <Confetti shape={piece.shape} colour={piece.colour} size={piece.size} />
        </span>
      ))}

      {CARDS.map((card, i) => (
        <span
          key={card.label}
          className="hero-drift absolute w-[168px] drop-shadow-[0_18px_34px_rgba(11,10,14,0.22)]"
          style={{
            left: `${card.left}%`,
            top: `${card.top}%`,
            animationDelay: `${(i * 1.4 + 0.3).toFixed(2)}s`,
            ["--tilt" as string]: `${card.tilt}deg`,
          }}
        >
          <span className="block rounded-[16px] bg-black p-2.5">
            <span className="block text-[10px] font-medium leading-none text-white/45">
              {card.label}
            </span>
            <span className="mt-2 block text-[19px] font-semibold tracking-tight text-white">
              {card.value}
            </span>
            <span className="block text-[9px] font-medium text-emerald-400">{card.delta}</span>
            {card.kind === "spark" ? <Spark colour={card.colour} /> : <Bars colour={card.colour} />}
          </span>
        </span>
      ))}

      {MARKS.map((mark, i) => {
        const manifest = manifests.get(mark.id);
        if (!manifest) return null;
        return (
          <span
            key={mark.id}
            className="hero-drift absolute drop-shadow-[0_12px_24px_rgba(11,10,14,0.18)]"
            style={{
              left: `${mark.left}%`,
              top: `${mark.top}%`,
              animationDelay: `${(i * 0.61).toFixed(2)}s`,
              ["--tilt" as string]: `${mark.tilt}deg`,
            }}
          >
            <ConnectorMark
              id={manifest.id}
              name={manifest.name}
              accentColor={manifest.accentColor}
              size={mark.size}
              shape="squircle"
            />
          </span>
        );
      })}
    </div>
  );
}

function Spark({ colour }: { colour: string }) {
  const line = SPARK.map((y, i) => `${Math.round((i * 154) / (SPARK.length - 1))},${y}`).join(" ");
  return (
    <svg viewBox="0 0 154 32" preserveAspectRatio="none" className="mt-2 h-10 w-full" aria-hidden>
      <polyline
        points={line}
        fill="none"
        stroke={colour}
        strokeWidth={1.75}
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

function Bars({ colour }: { colour: string }) {
  const max = Math.max(...BARS);
  return (
    <span className="mt-2 flex h-10 items-end gap-[3px]" aria-hidden>
      {BARS.map((value, index) => (
        <span
          key={index}
          className="flex-1 rounded-[2px]"
          style={{
            height: `${(value / max) * 100}%`,
            backgroundColor: colour,
            opacity: index === BARS.length - 1 ? 1 : 0.55,
          }}
        />
      ))}
    </span>
  );
}

function Confetti({ shape, colour, size }: { shape: string; colour: string; size: number }) {
  const common = { width: size, height: size, viewBox: "0 0 24 24", fill: "none" } as const;

  if (shape === "dot") {
    return (
      <svg {...common}>
        <circle cx="12" cy="12" r="12" fill={colour} />
      </svg>
    );
  }
  if (shape === "dash") {
    return (
      <svg {...common}>
        <path d="M2 12h20" stroke={colour} strokeWidth="3" strokeLinecap="round" />
      </svg>
    );
  }
  // The uptick: the one piece of confetti that is about the product.
  if (shape === "tick") {
    return (
      <svg {...common}>
        <path
          d="M2 18l6-7 5 4 9-11"
          stroke={colour}
          strokeWidth="2.75"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  return (
    <svg {...common}>
      <path
        d="M12 0c1.2 7.2 3.6 9.6 12 12-8.4 2.4-10.8 4.8-12 12-1.2-7.2-3.6-9.6-12-12C8.4 9.6 10.8 7.2 12 0Z"
        fill={colour}
      />
    </svg>
  );
}
