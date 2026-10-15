"use client";

import { useEffect, useState } from "react";

/**
 * The sticky contents rail beside a post, with the section you are reading
 * marked.
 *
 * The highlight comes from an IntersectionObserver rather than from scroll
 * maths: a heading's position changes as images above it load, and a reader
 * who lands on an anchor from a search result should see that section marked
 * before they scroll at all.
 *
 * `rootMargin` pulls the observed band up to just under the fixed nav and
 * down to a sliver, so exactly one heading is ever inside it: the last one
 * to have crossed the top of the viewport.
 */
export function PostToc({ headings }: { headings: { id: string; text: string }[] }) {
  const [active, setActive] = useState<string | null>(headings[0]?.id ?? null);

  useEffect(() => {
    const elements = headings
      .map((heading) => document.getElementById(heading.id))
      .filter((element): element is HTMLElement => element !== null);
    if (elements.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setActive(entry.target.id);
        }
      },
      { rootMargin: "-120px 0px -75% 0px", threshold: 0 },
    );

    for (const element of elements) observer.observe(element);
    return () => observer.disconnect();
  }, [headings]);

  return (
    <nav aria-label="On this page" className="sticky top-28">
      <p className="eyebrow">On this page</p>
      <ul className="border-ink/[0.07] mt-4 flex flex-col gap-0.5 border-l">
        {headings.map((heading) => {
          const current = heading.id === active;
          return (
            <li key={heading.id}>
              <a
                href={`#${heading.id}`}
                aria-current={current ? "location" : undefined}
                className={`-ml-px block border-l py-1.5 pl-4 text-[13.5px] leading-snug transition ${
                  current
                    ? "border-ink text-ink font-medium"
                    : "text-ink/45 hover:text-ink border-transparent"
                }`}
              >
                {heading.text}
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
