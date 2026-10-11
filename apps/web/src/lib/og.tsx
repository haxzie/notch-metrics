import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ImageResponse } from "next/og";

/**
 * The social card, drawn once and reused by every route that has one.
 *
 * Read with `node:fs` and therefore build-time only, like `src/lib/blog.ts`:
 * every caller is a route with `generateStaticParams`, so the cards are PNGs
 * on disk by the time the Worker serves them. A card generated on request
 * would need `fs` and a font loader inside the Worker and would fail there.
 *
 * Satori, not a browser. It supports a subset of CSS: no `background-clip`,
 * no custom properties, no external stylesheet. Everything below is an inline
 * style with a literal colour, and the brand gradient is a real
 * `linear-gradient` rather than the `.brand-text` class the site uses.
 */
export const OG_SIZE = { width: 1200, height: 630 };
export const OG_CONTENT_TYPE = "image/png";

const INK = "#070608";
const BRAND_START = "#d819c2";
const BRAND_END = "#ffc107";

/** The app icon, inlined. Satori cannot fetch a relative asset path. */
function appIcon(): string {
  const bytes = readFileSync(join(process.cwd(), "public", "logo.svg"));
  return `data:image/svg+xml;base64,${bytes.toString("base64")}`;
}

/**
 * Title length is the one thing to watch.
 *
 * Satori neither truncates nor shrinks: a title past roughly eighty
 * characters runs off the bottom of the card rather than wrapping into it.
 * The size steps down once instead of clipping.
 */
export function ogCard({
  kicker,
  title,
  footnote,
}: {
  kicker: string;
  title: string;
  footnote?: string;
}): ImageResponse {
  const fontSize = title.length > 58 ? 58 : 72;

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        background: INK,
        padding: "72px 80px",
        position: "relative",
      }}
    >
      {/* The glow, as two blurred blocks. Satori has no filter, so this is
            a radial gradient instead. */}
      <div
        style={{
          position: "absolute",
          top: -260,
          left: 320,
          width: 700,
          height: 560,
          background: `radial-gradient(circle, ${BRAND_START}33 0%, ${INK}00 70%)`,
        }}
      />

      <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={appIcon()} width={52} height={52} alt="" />
        <span
          style={{
            fontSize: 22,
            letterSpacing: 2.6,
            textTransform: "uppercase",
            color: "rgba(255,255,255,0.45)",
          }}
        >
          {kicker}
        </span>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
        <div
          style={{
            fontSize,
            lineHeight: 1.08,
            fontWeight: 600,
            letterSpacing: -1.6,
            color: "#f5f3f7",
            display: "flex",
          }}
        >
          {title}
        </div>
        {footnote ? (
          <div style={{ fontSize: 26, color: "rgba(255,255,255,0.45)", display: "flex" }}>
            {footnote}
          </div>
        ) : null}
      </div>

      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span style={{ fontSize: 28, fontWeight: 600, color: "#f5f3f7" }}>Notch Metrics</span>
        <div
          style={{
            width: 180,
            height: 6,
            borderRadius: 3,
            background: `linear-gradient(90deg, ${BRAND_START}, ${BRAND_END})`,
          }}
        />
      </div>
    </div>,
    OG_SIZE,
  );
}
