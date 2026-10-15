"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AppleMark } from "./icons";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/#pricing", label: "Pricing" },
  { href: "/sources", label: "Sources" },
  { href: "/blog", label: "Blog" },
  { href: "/login", label: "Sign in" },
];

export function SiteNav() {
  const pathname = usePathname();

  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-5">
      <nav className="border-ink/[0.07] bg-paper/75 pointer-events-auto relative flex h-14 w-full max-w-3xl items-center justify-between rounded-full border pl-5 pr-2 shadow-[0_8px_30px_-12px_rgba(11,10,14,0.18)] backdrop-blur-xl">
        <Link href="/" className="flex w-fit items-center gap-2.5 text-[15px] font-semibold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" width={24} height={24} />
          <span className="hidden sm:inline">Notch Metrics</span>
        </Link>

        <ul className="absolute left-1/2 hidden -translate-x-1/2 items-center gap-1 sm:flex">
          {LINKS.map((link) => {
            // Prefix matching for everything but "/", so a post at
            // /blog/<slug> still lights up Blog. An equality check left the
            // nav with nothing selected on every page below the top level.
            const active = link.href === "/" ? pathname === "/" : pathname.startsWith(link.href);
            return (
              <li key={link.href}>
                <Link
                  href={link.href}
                  className={`rounded-full px-3.5 py-2 text-[14px] transition ${
                    active ? "text-ink" : "text-ink/55 hover:text-ink"
                  }`}
                >
                  {link.label}
                </Link>
              </li>
            );
          })}
        </ul>

        <Link
          href="/download"
          className="bg-ink hover:bg-ink/85 flex h-10 w-fit items-center gap-2 rounded-full px-4 text-[14px] font-semibold text-white transition"
        >
          <AppleMark className="h-4 w-4" />
          Download
        </Link>
      </nav>
    </header>
  );
}
