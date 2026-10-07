"use client";

import { useState } from "react";
import {
  FULL_BLEED_MARKS,
  LIGHT_TILE_MARKS,
  OWN_COLOUR_MARKS,
} from "@/lib/connector-marks.generated";
import { liftForDarkUI } from "@/lib/brand-colour";

/**
 * A connector's brand mark on a tile.
 *
 * Mirrors `ConnectorIcon` in the Mac app: a mark drawn for a light background
 * gets a near-white tile, everything else sits on the brand's own colour. The
 * brand colour takes a luminance floor, because those are picked against a
 * white page and several vanish into this one.
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
  const lightTile = LIGHT_TILE_MARKS.has(id);
  // Artwork that already is the tile is drawn to the edges, clipped to the
  // same corner radius, rather than floated inside a second square.
  const fullBleed = FULL_BLEED_MARKS.has(id);
  const glyph = fullBleed ? size : Math.round(size * (lightTile ? 0.62 : 0.54));

  return (
    <span
      className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-[26%] ring-1 ${
        lightTile ? "ring-white/25" : "ring-white/10"
      }`}
      style={{
        width: size,
        height: size,
        // Not pure white: a hard #fff square is brighter than anything else
        // on a dark page and a list of them reads as headlights.
        // The luminance floor keeps a white glyph legible; a mark with its
        // own colours does not need it, and lifting Dodo Payments' black to
        // grey only washes the tile out behind its lime.
        backgroundColor: lightTile
          ? "#f5f5f5"
          : OWN_COLOUR_MARKS.has(id)
            ? accentColor
            : liftForDarkUI(accentColor),
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
