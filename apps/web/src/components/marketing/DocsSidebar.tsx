"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/**
 * The left rail: every page, grouped, with the current one marked.
 *
 * A client component only for `usePathname`. The pages themselves stay
 * static, and the groups are computed on the server and passed in, so nothing
 * here reads the content collection.
 *
 * Sticky under the fixed nav, and hidden below `xl` where the blog's layout
 * hides its own rail. A docs sidebar collapsed into a phone-width accordion
 * is a second navigation model to maintain, and the index page already lists
 * every page as a card.
 */
export type SidebarGroup = {
  label: string;
  docs: { slug: string; title: string }[];
};

export function DocsSidebar({ groups }: { groups: SidebarGroup[] }) {
  const pathname = usePathname();

  return (
    <nav aria-label="Documentation" className="hidden xl:block">
      {/* `-mx-3 px-3` so the active pill, which is pulled out by the same
            amount to sit its text under the eyebrow, is not sliced by this
            box. `overflow-y: auto` clips the X axis too, so without the room
            the pill lost its rounded left edge. */}
      <div className="sticky top-28 -mx-3 max-h-[calc(100vh-9rem)] overflow-y-auto px-3 pb-10">
        {groups.map((group, index) => (
          <div key={group.label} className={index === 0 ? "" : "mt-7"}>
            <p className="eyebrow">{group.label}</p>
            <ul className="mt-2.5 space-y-0.5">
              {group.docs.map((doc) => {
                // An empty slug is the index route, which is the
                // introduction. See `sidebarGroups`.
                const href = doc.slug === "" ? "/docs" : `/docs/${doc.slug}`;
                const active = pathname === href;
                return (
                  <li key={href}>
                    <Link
                      href={href}
                      aria-current={active ? "page" : undefined}
                      className={`-ml-3 block rounded-lg px-3 py-1.5 text-[13.5px] leading-snug transition ${
                        active ? "bg-ink/[0.05] text-ink font-medium" : "text-ink/55 hover:text-ink"
                      }`}
                    >
                      {doc.title}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </div>
    </nav>
  );
}
