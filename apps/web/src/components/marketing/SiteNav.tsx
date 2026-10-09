"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AppleMark } from "./icons";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/pricing", label: "Pricing" },
  { href: "https://github.com/haxzie/notch-metrics", label: "GitHub", external: true },
];

export function SiteNav() {
  const pathname = usePathname();

  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <nav className="pointer-events-auto flex h-12 items-center gap-1 rounded-full border border-white/[0.08] bg-[#141216]/80 pl-4 pr-1.5 shadow-[0_8px_40px_-12px_rgba(0,0,0,0.8)] backdrop-blur-xl">
        <Link href="/" className="mr-3 flex items-center gap-2 text-sm font-semibold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" width={20} height={20} />
          <span className="hidden sm:inline">Notch Metrics</span>
        </Link>

        <ul className="hidden items-center sm:flex">
          {LINKS.map((link) => {
            const active = !link.external && pathname === link.href;
            return (
              <li key={link.href}>
                <Link
                  href={link.href}
                  target={link.external ? "_blank" : undefined}
                  rel={link.external ? "noreferrer" : undefined}
                  className={`rounded-full px-3 py-1.5 text-[13px] transition ${
                    active ? "text-white" : "text-white/55 hover:text-white"
                  }`}
                >
                  {link.label}
                </Link>
              </li>
            );
          })}
          <li>
            <Link
              href="/login"
              className="rounded-full px-3 py-1.5 text-[13px] text-white/55 transition hover:text-white"
            >
              Sign in
            </Link>
          </li>
        </ul>

        <Link
          href="/download"
          className="ml-2 flex h-9 items-center gap-1.5 rounded-full bg-white px-3.5 text-[13px] font-semibold text-black transition hover:bg-white/90"
        >
          <AppleMark className="h-3.5 w-3.5" />
          Download
        </Link>
      </nav>
    </header>
  );
}
