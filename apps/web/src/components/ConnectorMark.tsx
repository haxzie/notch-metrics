"use client";

import { useState } from "react";

/**
 * A connector's brand mark on a tile of its own colour.
 *
 * Mirrors `ConnectorIcon` in the Mac app, including the luminance floor —
 * brand colours are picked against a white page and several of them vanish
 * into this one.
 */
export function ConnectorMark({
  id,
  name,
  accentColor,
  size = 36,
}: {
  id: string;
  name: string;
  accentColor: string;
  size?: number;
}) {
  // Four connectors have no vendored mark. They fall back to a lettermark
  // rather than a broken image, so the row still looks deliberate.
  const [hasMark, setHasMark] = useState(true);

  return (
    <span
      className="inline-flex shrink-0 items-center justify-center rounded-[26%] ring-1 ring-white/10"
      style={{ width: size, height: size, backgroundColor: liftForDarkUI(accentColor) }}
      title={name}
    >
      {hasMark ? (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img
          src={`/connectors/${id}.svg`}
          alt=""
          width={Math.round(size * 0.54)}
          height={Math.round(size * 0.54)}
          onError={() => setHasMark(false)}
        />
      ) : (
        <span
          className="font-semibold text-white"
          style={{ fontSize: Math.round(size * 0.42) }}
          aria-hidden
        >
          {name.charAt(0).toUpperCase()}
        </span>
      )}
      <span className="sr-only">{name}</span>
    </span>
  );
}

/** Rec. 709 luma, same floor as the Mac app's `NotchTheme.tileFill`. */
function liftForDarkUI(hex: string): string {
  const value = Number.parseInt(hex.replace("#", ""), 16);
  if (Number.isNaN(value)) return "#6b7280";

  let r = (value >> 16) & 0xff;
  let g = (value >> 8) & 0xff;
  let b = value & 0xff;

  const luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  if (luma >= 0.16) return hex;

  // Scale toward white rather than shifting hue: what people recognise about
  // a brand colour is the hue, not the brightness.
  const lift = 0.28 / Math.max(luma, 0.04);
  r = Math.min(255, Math.round(r * lift) + 28);
  g = Math.min(255, Math.round(g * lift) + 28);
  b = Math.min(255, Math.round(b * lift) + 28);
  return `#${[r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("")}`;
}
