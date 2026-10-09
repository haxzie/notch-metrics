"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AppleMark } from "./icons";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/pricing", label: "Pricing" },
  { href: "/login", label: "Sign in" },
];

export function SiteNav() {
  const pathname = usePathname();

  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-5">
      <nav className="pointer-events-auto flex h-14 items-center gap-1 rounded-full border border-white/[0.08] bg-[#141216]/80 pl-5 pr-2 shadow-[0_8px_40px_-12px_rgba(0,0,0,0.8)] backdrop-blur-xl">
        <Link href="/" className="mr-4 flex items-center gap-2.5 text-[15px] font-semibold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" width={24} height={24} />
          <span className="hidden sm:inline">Notch Metrics</span>
        </Link>

        <ul className="hidden items-center sm:flex">
          {LINKS.map((link) => {
            const active = pathname === link.href;
            return (
              <li key={link.href}>
                <Link
                  href={link.href}
                  className={`rounded-full px-3.5 py-2 text-[14px] transition ${
                    active ? "text-white" : "text-white/55 hover:text-white"
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
          className="ml-3 flex h-10 items-center gap-2 rounded-full bg-white px-4 text-[14px] font-semibold text-black transition hover:bg-white/90"
        >
          <AppleMark className="h-4 w-4" />
          Download
        </Link>
      </nav>
    </header>
  );
}
