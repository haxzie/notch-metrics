import Link from "next/link";
import { PLANS, formatPrice } from "@notch/schemas";
import { ConnectorMark } from "@/components/ConnectorMark";

/**
 * The card that rides beside a post.
 *
 * A reader here arrived from a search for "how do I calculate MRR from
 * Paddle", so the pitch is the thing they were about to go and do by hand.
 * It carries the price because a card that hides it costs a click to find
 * out, and most people leave instead.
 */
export function PostCta() {
  return (
    <aside className="sticky top-28">
      <div className="border-ink/[0.07] overflow-hidden rounded-[24px] border bg-white shadow-[0_1px_2px_rgba(11,10,14,0.04),0_18px_40px_-28px_rgba(11,10,14,0.2)]">
        {/* The notch, with a number in it, over the sources it came from. */}
        <div className="bg-ink/[0.04] relative flex h-[136px] justify-center overflow-hidden">
          <Scatter />
          <div className="bg-ink relative z-10 flex h-[34px] w-[152px] items-center justify-center gap-2 rounded-b-[14px] px-3">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-400" />
            <span className="font-mono text-[13px] font-medium text-white">$12,480</span>
          </div>
        </div>

        <div className="p-5">
          <p className="text-[15px] font-semibold tracking-tight">Put your metrics in the notch</p>
          <p className="text-ink/55 mt-2 text-[13.5px] leading-relaxed">
            Notch Metrics keeps this number on your MacBook, where you already look. No tab, no
            dashboard.
          </p>

          <Link
            href="/download"
            className="bg-ink hover:bg-ink/85 mt-4 flex h-10 w-full items-center justify-center rounded-full text-[13.5px] font-semibold text-white transition"
          >
            Download for Mac
          </Link>
          <p className="text-ink/40 mt-3 text-center font-mono text-[10.5px] tracking-wide">
            Seven days free · {formatPrice(PLANS.pro.amount, "USD")} a month
          </p>
        </div>
      </div>
    </aside>
  );
}

/**
 * The sources behind the notch, as if dropped into the box.
 *
 * Depth comes from three things at once: size, how far the mark is turned,
 * and how much of the card's own background is laid over it. Hand-placed
 * rather than randomised, because a random seed puts one of them under the
 * notch about a third of the time, and because the server and the client
 * have to agree on where they are.
 */
const SCATTER: {
  id: string;
  name: string;
  accent: string;
  left: number;
  top: number;
  size: number;
  tilt: number;
  /** 0 is right at the front, 1 is furthest back. */
  depth: number;
}[] = [
  {
    id: "stripe",
    name: "Stripe",
    accent: "#635BFF",
    left: 2,
    top: 44,
    size: 38,
    tilt: -12,
    depth: 0,
  },
  {
    id: "shopify",
    name: "Shopify",
    accent: "#95BF47",
    left: 78,
    top: 52,
    size: 36,
    tilt: 11,
    depth: 0,
  },
  {
    id: "polar",
    name: "Polar",
    accent: "#090909",
    left: 24,
    top: 74,
    size: 30,
    tilt: 7,
    depth: 0.3,
  },
  {
    id: "paddle",
    name: "Paddle",
    accent: "#FDDD35",
    left: 56,
    top: 78,
    size: 28,
    tilt: -8,
    depth: 0.3,
  },
  {
    id: "github",
    name: "GitHub",
    accent: "#181717",
    left: 12,
    top: 10,
    size: 24,
    tilt: 9,
    depth: 0.6,
  },
  {
    id: "plausible",
    name: "Plausible",
    accent: "#5850EC",
    left: 82,
    top: 8,
    size: 22,
    tilt: -10,
    depth: 0.6,
  },
  {
    id: "revenuecat",
    name: "RevenueCat",
    accent: "#F2545B",
    left: 44,
    top: 40,
    size: 20,
    tilt: 6,
    depth: 0.8,
  },
];

function Scatter() {
  return (
    <span aria-hidden className="absolute inset-0">
      {SCATTER.map((mark) => (
        <span
          key={mark.id}
          className="absolute"
          style={{
            left: `${mark.left}%`,
            top: `${mark.top}%`,
            transform: `rotate(${mark.tilt}deg)`,
            // The far ones sit back rather than fading out: full transparency
            // on a tinted panel reads as a mistake, a soft one reads as depth.
            opacity: 1 - mark.depth * 0.65,
            // Blur the far ones, and let the near ones cast a shadow: the
            // two together are what read as distance rather than as a mark
            // that failed to load.
            filter:
              mark.depth > 0.5
                ? "blur(0.6px)"
                : mark.depth === 0
                  ? "drop-shadow(0 6px 12px rgba(11,10,14,0.22))"
                  : undefined,
          }}
        >
          <ConnectorMark
            id={mark.id}
            name={mark.name}
            accentColor={mark.accent}
            size={mark.size}
            shape="squircle"
          />
        </span>
      ))}
    </span>
  );
}
