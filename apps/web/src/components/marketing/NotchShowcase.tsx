"use client";

import { useEffect, useState } from "react";
import { NotchMockup } from "./NotchMockup";
import { PERSONAS } from "./personas";

/**
 * One Mac, one notch, and a picker for whose setup is in it.
 *
 * The picker lives on the desktop inside the screen, between the arrows,
 * because the point of the section is that the notch is part of a machine.
 * A row of tabs floating above the frame made the mockup an illustration
 * sitting under a control panel.
 */
export function NotchShowcase() {
  const [index, setIndex] = useState(0);
  const count = PERSONAS.length;
  const go = (next: number) => setIndex((next + count) % count);
  const persona = PERSONAS[index] ?? PERSONAS[0];

  // `?persona=founders` opens on that setup, so a link can land someone on
  // the one meant for them. Read in an effect rather than from
  // useSearchParams so the hero needs no Suspense boundary and the server
  // render is identical for every URL.
  useEffect(() => {
    const wanted = new URLSearchParams(window.location.search).get("persona");
    const found = PERSONAS.findIndex((p) => p.id === wanted);
    if (found >= 0) setIndex(found);
  }, []);

  return (
    <NotchMockup
      widgets={persona?.widgets ?? []}
      controls={
        <div className="flex items-center gap-2">
          <Arrow label="Previous setup" onClick={() => go(index - 1)} />
          <div
            role="tablist"
            aria-label="Who it is for"
            className="border-ink/[0.06] flex items-center gap-1 rounded-full border bg-white/80 p-1 shadow-[0_10px_30px_-14px_rgba(11,10,14,0.4)] backdrop-blur-xl"
          >
            {PERSONAS.map((option, i) => {
              const active = i === index;
              return (
                <button
                  key={option.id}
                  role="tab"
                  type="button"
                  aria-selected={active}
                  onClick={() => setIndex(i)}
                  className={`rounded-full px-3.5 py-1.5 text-[13px] font-medium transition sm:px-4 ${
                    active ? "bg-ink text-white" : "text-ink/55 hover:text-ink"
                  }`}
                >
                  {option.label}
                </button>
              );
            })}
          </div>
          <Arrow label="Next setup" onClick={() => go(index + 1)} flip />
        </div>
      }
    />
  );
}

function Arrow({ label, onClick, flip }: { label: string; onClick: () => void; flip?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className="border-ink/[0.06] text-ink/60 hover:text-ink flex h-10 w-10 shrink-0 items-center justify-center rounded-full border bg-white/80 shadow-[0_10px_30px_-14px_rgba(11,10,14,0.4)] backdrop-blur-xl transition"
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.75}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={`h-[18px] w-[18px] ${flip ? "" : "rotate-180"}`}
        aria-hidden
      >
        <path d="M5 12h14M13 6l6 6-6 6" />
      </svg>
    </button>
  );
}
