"use client";

import { useEffect, useState } from "react";
import { NotchMockup } from "./NotchMockup";
import { PERSONAS } from "./personas";

/**
 * The hero's slideshow: one notch per persona, a pill of tabs above and an
 * arrow either side.
 *
 * The slides are a ring, not a strip. Each is placed by its distance from
 * the active one, so there is always a card peeking in from both edges —
 * including to the left of the first — and moving on reads as the next
 * setup sliding into the middle rather than the current one being replaced.
 * A slide more than one step away is hidden while it travels round the back.
 */
export function NotchShowcase() {
  const [index, setIndex] = useState(0);
  const count = PERSONAS.length;
  const go = (next: number) => setIndex((next + count) % count);

  // `?persona=founders` opens on that slide, so a link can land someone on
  // the setup meant for them. Read in an effect rather than from
  // useSearchParams so the hero needs no Suspense boundary and the server
  // render is identical for every URL.
  useEffect(() => {
    const wanted = new URLSearchParams(window.location.search).get("persona");
    const found = PERSONAS.findIndex((persona) => persona.id === wanted);
    if (found >= 0) setIndex(found);
  }, []);

  // Signed distance from the active slide, wrapped so the ring is balanced:
  // with four slides the offsets are -1, 0, 1, 2.
  const offsetOf = (i: number) => {
    const raw = (((i - index) % count) + count) % count;
    return raw > count / 2 ? raw - count : raw;
  };

  return (
    <div className="flex flex-col items-center gap-8">
      <div
        role="tablist"
        aria-label="Who it is for"
        className="flex items-center gap-1 rounded-full border border-white/[0.08] bg-white/[0.04] p-1"
      >
        {PERSONAS.map((persona, i) => {
          const active = i === index;
          return (
            <button
              key={persona.id}
              role="tab"
              type="button"
              aria-selected={active}
              onClick={() => setIndex(i)}
              className={`rounded-full px-4 py-1.5 text-[13px] font-medium transition sm:px-5 sm:text-sm ${
                active ? "bg-white text-black shadow-sm" : "text-white/55 hover:text-white"
              }`}
            >
              {persona.label}
            </button>
          );
        })}
      </div>

      {/* The height is the mockup's own, so the absolutely placed slides
          have something to stand in. */}
      <div className="relative h-[502px] w-full sm:h-[522px]">
        {PERSONAS.map((persona, i) => {
          const offset = offsetOf(i);
          const near = Math.abs(offset) <= 1;
          return (
            <div
              key={persona.id}
              role="tabpanel"
              aria-hidden={offset !== 0}
              className="absolute inset-0 transition-[transform,opacity] duration-500 ease-[cubic-bezier(0.22,1,0.36,1)]"
              style={{
                // Neighbours sit one width over, then pull in and shrink so
                // their inner edge shows beside the active card.
                transform: `translateX(${offset * 100}%) translateX(${-offset * 24}%) scale(${
                  offset === 0 ? 1 : 0.84
                })`,
                opacity: offset === 0 ? 1 : near ? 0.4 : 0,
                zIndex: offset === 0 ? 20 : near ? 10 : 0,
                pointerEvents: near ? "auto" : "none",
              }}
              onClick={offset === 0 ? undefined : () => setIndex(i)}
            >
              <NotchMockup widgets={persona.widgets} />
            </div>
          );
        })}

        <Arrow side="left" label="Previous setup" onClick={() => go(index - 1)} />
        <Arrow side="right" label="Next setup" onClick={() => go(index + 1)} />
      </div>
    </div>
  );
}

function Arrow({
  side,
  label,
  onClick,
}: {
  side: "left" | "right";
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className={`absolute top-1/2 z-30 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border border-white/10 bg-[#141216]/80 text-white/70 shadow-[0_8px_30px_-10px_rgba(0,0,0,0.8)] backdrop-blur-xl transition hover:bg-white/10 hover:text-white ${
        side === "left" ? "left-3 lg:-left-6" : "right-3 lg:-right-6"
      }`}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.75}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={`h-5 w-5 ${side === "left" ? "rotate-180" : ""}`}
        aria-hidden
      >
        <path d="M5 12h14M13 6l6 6-6 6" />
      </svg>
    </button>
  );
}
