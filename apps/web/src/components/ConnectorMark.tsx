"use client";

import { useState } from "react";
import { FULL_COLOUR_MARKS } from "@/lib/connector-marks.generated";
import { liftForDarkUI } from "@/lib/brand-colour";

/**
 * A connector's brand mark on a tile.
 *
 * Mirrors `ConnectorIcon` in the Mac app: a full-colour official mark sits on
 * a near-white tile at its own colours, a monochrome simple-icons glyph sits
 * white on the brand's colour. The brand colour also takes a luminance floor,
 * because those are picked against a white page and several vanish into this
 * one.
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
  const fullColour = FULL_COLOUR_MARKS.has(id);
  const glyph = Math.round(size * (fullColour ? 0.62 : 0.54));

  return (
    <span
      className={`inline-flex shrink-0 items-center justify-center rounded-[26%] ring-1 ${
        fullColour ? "ring-white/25" : "ring-white/10"
      }`}
      style={{
        width: size,
        height: size,
        // Not pure white: a hard #fff square is brighter than anything else
        // on a dark page and a list of them reads as headlights.
        backgroundColor: fullColour ? "#f5f5f5" : liftForDarkUI(accentColor),
      }}
      title={name}
    >
      {hasMark ? (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img
          src={`/connectors/${id}.svg`}
          alt=""
          width={glyph}
          height={glyph}
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
