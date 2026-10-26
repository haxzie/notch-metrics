import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { catalogue } from "@notch/integrations";
import { OG_SIZE } from "@/lib/og";

/**
 * The home page's social card, built from the hero.
 *
 * Separate from `ogCard`, which is the dark title card every *article* uses.
 * This one is the landing page, so it is the landing page's own surface:
 * paper, ink, and the field of connector marks that sits behind the
 * headline. A card that looked nothing like the page it links to is a card
 * that makes the click feel like a mistake.
 *
 * Satori, not a browser. No `background-clip`, no custom properties, no
 * external stylesheet, and `position: absolute` children need a parent with
 * `display: flex` set explicitly. Every colour below is a literal rather
 * than a `var(--color-ink)` the renderer cannot resolve.
 */
const PAPER = "#fbfafc";
const INK = "#0b0a0e";
const AMBER = "#ffc107";

/**
 * A connector's brand colour, from the same manifests the site reads.
 *
 * Looked up rather than hard-coded: a provider that rebrands changes one
 * manifest and this follows, where a literal here would quietly keep the old
 * colour on every share of the home page.
 */
function accent(id: string): string {
  const connector = catalogue()
    .flatMap((group) => group.connectors)
    .find((entry) => entry.id === id);
  // Ink, not magenta: a missing colour should look deliberate on a card
  // nobody will see a build error for.
  return connector?.accentColor ?? INK;
}

/**
 * Inter, in the two weights the card uses.
 *
 * The site itself sets no webfont: its stack is `ui-sans-serif`, which is SF
 * Pro on a Mac. Satori has no system fonts at all, so without this the card
 * renders in whatever `next/og` bundles — Geist Regular — and
 * `fontWeight: 700` does nothing, because a weight that is not loaded cannot
 * be synthesised.
 *
 * Inter rather than SF Pro: SF is not redistributable, and the website is
 * built on Linux CI where it does not exist, so reading it from
 * `/System/Library/Fonts` would match on one Mac and silently fall back in
 * production. Inter is the closest open face and is what the card is drawn
 * against.
 *
 * `.woff`, not `.woff2`: Satori reads the first and not the second.
 */
function inter(weight: 400 | 700): Buffer {
  return readFileSync(
    join(
      process.cwd(),
      "node_modules",
      "@fontsource",
      "inter",
      "files",
      `inter-latin-${weight}-normal.woff`,
    ),
  );
}

/** An asset from `public/`, inlined. Satori cannot fetch a relative path. */
function asset(...segments: string[]): string {
  const bytes = readFileSync(join(process.cwd(), "public", ...segments));
  return `data:image/svg+xml;base64,${bytes.toString("base64")}`;
}

/**
 * The marks that flank the headline, in two bands.
 *
 * Hand-placed against this canvas rather than reused from `HeroGlyphs`: that
 * component positions in percentages of a viewport it shares with a nav, a
 * sub-head and two buttons, and those percentages land on the words here.
 * The two sets are the same idea at different sizes, which is the one case
 * where a copy beats a shared constant.
 *
 * Every id here is a plain white glyph that sits on its brand's colour, and
 * every one ships a vendored mark. `ConnectorMark` has three other cases — a
 * near-white tile for marks drawn for light backgrounds, artwork that is
 * already its own colour, and one full-bleed logo — and reproducing that
 * ladder in Satori for a decorative layer is not worth it.
 *
 * Mixpanel is deliberately absent even though it has a mark: it is
 * `coming_soon`, and a marketing card must not show a connector that does
 * not work yet.
 */
const MARKS: { id: string; x: number; y: number; size: number; tilt: number }[] = [
  // Placed around the two tiles, never behind them. The tiles occupy
  // x 40-248 and x 952-1160 between y 176 and y 360, and a mark dropped in
  // either box disappears underneath it: the first pass lost Shopify and
  // Lemon Squeezy entirely and clipped Paddle's corner.
  { id: "stripe", x: 56, y: 92, size: 68, tilt: -9 },
  { id: "shopify", x: 192, y: 104, size: 52, tilt: 7 },
  { id: "revenuecat", x: 74, y: 430, size: 60, tilt: -6 },
  { id: "plausible", x: 198, y: 528, size: 46, tilt: 8 },
  { id: "paddle", x: 1114, y: 92, size: 62, tilt: 8 },
  { id: "lemonsqueezy", x: 1118, y: 386, size: 52, tilt: -7 },
  { id: "youtube", x: 972, y: 470, size: 58, tilt: 6 },
];

/** The amber flecks between them. Two colours is the whole palette. */
const CONFETTI: { x: number; y: number; size: number }[] = [
  { x: 206, y: 150, size: 12 },
  { x: 104, y: 346, size: 8 },
  { x: 232, y: 420, size: 10 },
  { x: 962, y: 206, size: 10 },
  { x: 1086, y: 404, size: 12 },
  { x: 944, y: 516, size: 8 },
];

/** One of the app's own tiles, which is what says what the marks are *for*. */
function tile({
  x,
  y,
  tilt,
  label,
  value,
  delta,
  bars,
}: {
  x: number;
  y: number;
  tilt: number;
  label: string;
  value: string;
  delta: string;
  bars: number[];
}) {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 208,
        display: "flex",
        flexDirection: "column",
        gap: 6,
        padding: "16px 18px",
        borderRadius: 18,
        background: "#ffffff",
        border: "1px solid rgba(11,10,14,0.06)",
        boxShadow: "0 18px 40px -24px rgba(11,10,14,0.35)",
        transform: `rotate(${tilt}deg)`,
      }}
    >
      <span style={{ fontSize: 15, color: "rgba(11,10,14,0.5)" }}>{label}</span>
      <span style={{ fontSize: 30, fontWeight: 600, color: INK, letterSpacing: -0.8 }}>
        {value}
      </span>
      <span style={{ fontSize: 13, color: "#1a8f4a" }}>{delta}</span>
      {/* Bars rather than a path: Satori has no SVG `d` renderer worth
          relying on, and six divs say "a number over time" just as well. */}
      <div style={{ display: "flex", alignItems: "flex-end", gap: 5, height: 40, marginTop: 6 }}>
        {bars.map((height, index) => (
          <div
            key={index}
            style={{
              width: 18,
              height,
              borderRadius: 4,
              background: index === bars.length - 1 ? INK : "rgba(11,10,14,0.14)",
            }}
          />
        ))}
      </div>
    </div>
  );
}

/** The headline's own type size. The glyphs are sized from it. */
const TITLE = 70;

/**
 * The app's mark on an ink tile, as the hero sets it mid-sentence.
 *
 * The file rather than an inline path: the mark's colours are a gradient
 * defined inside the SVG, and this is the one place that wants them rather
 * than a flat fill.
 */
function chartGlyph() {
  const box = TITLE * 0.88;
  return (
    <div
      style={{
        width: box,
        height: box,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        borderRadius: box * 0.24,
        background: INK,
        transform: "rotate(-6deg)",
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={asset("logo.svg")} width={box * 0.62} height={box * 0.62} alt="" />
    </div>
  );
}

/**
 * The top of a MacBook display with the notch in it.
 *
 * Black glass, a light desktop, and the notch hanging into it. The light
 * screen is what makes the shape a notch; drawn as a black tab alone it
 * reads as a dash.
 */
function notchGlyph() {
  const height = TITLE * 0.72;
  const width = TITLE * 1.3;
  const pad = TITLE * 0.07;
  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        padding: pad,
        borderRadius: TITLE * 0.2,
        background: INK,
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          justifyContent: "center",
          borderRadius: TITLE * 0.13,
          background: "#f1ecf5",
        }}
      >
        <div
          style={{
            width: "40%",
            height: "36%",
            background: INK,
            borderBottomLeftRadius: TITLE * 0.07,
            borderBottomRightRadius: TITLE * 0.07,
          }}
        />
      </div>
    </div>
  );
}

export function ogHero(): ImageResponse {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        background: PAPER,
        position: "relative",
        fontFamily: "Inter",
      }}
    >
      {MARKS.map((mark) => (
        <div
          key={mark.id}
          style={{
            position: "absolute",
            left: mark.x,
            top: mark.y,
            width: mark.size,
            height: mark.size,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: mark.size * 0.26,
            background: accent(mark.id),
            boxShadow: "0 14px 30px -18px rgba(11,10,14,0.5)",
            transform: `rotate(${mark.tilt}deg)`,
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={asset("connectors", `${mark.id}.svg`)}
            width={mark.size * 0.56}
            height={mark.size * 0.56}
            alt=""
          />
        </div>
      ))}

      {CONFETTI.map((fleck, index) => (
        <div
          key={index}
          style={{
            position: "absolute",
            left: fleck.x,
            top: fleck.y,
            width: fleck.size,
            height: fleck.size,
            borderRadius: fleck.size / 2,
            background: AMBER,
          }}
        />
      ))}

      {tile({
        x: 40,
        y: 196,
        tilt: -6,
        label: "MRR",
        value: "$12,480",
        delta: "+4.2% vs last month",
        bars: [9, 17, 13, 26, 22, 40],
      })}
      {tile({
        x: 952,
        y: 176,
        tilt: 6,
        label: "Revenue · 7d",
        value: "$3,920",
        delta: "+11% vs last week",
        bars: [11, 15, 21, 18, 29, 40],
      })}

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 26,
          padding: "0 300px",
        }}
      >
        {/* The headline exactly as the hero sets it, glyphs and all. The
            two marks are part of the sentence there, and a card that drops
            them is a card for a different page. */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 6,
            fontSize: TITLE,
            lineHeight: 1,
            fontWeight: 700,
            letterSpacing: -2.8,
            color: INK,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <span>Put your</span>
            {chartGlyph()}
            <span>metrics</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <span>in the notch</span>
            {notchGlyph()}
          </div>
        </div>
        <span
          style={{
            fontSize: 25,
            color: "rgba(11,10,14,0.55)",
            textAlign: "center",
            lineHeight: 1.35,
          }}
        >
          A live dashboard in your notch. Nothing to open.
        </span>
      </div>
    </div>,
    {
      ...OG_SIZE,
      fonts: [
        { name: "Inter", data: inter(400), weight: 400, style: "normal" },
        { name: "Inter", data: inter(700), weight: 700, style: "normal" },
      ],
    },
  );
}
