"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut, useSession } from "@/lib/auth-client";

const NAV = [
  { href: "/app", label: "Overview" },
  { href: "/app/integrations", label: "Integrations" },
  { href: "/app/settings/billing", label: "Billing" },
];

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { data: session, isPending } = useSession();
  const pathname = usePathname();

  // A client-side guard, not a security boundary — every route this page
  // calls is authorised on the Worker. This only avoids rendering a shell
  // full of empty states to somebody who is simply signed out.
  if (!isPending && !session) {
    if (typeof window !== "undefined") {
      window.location.replace(`/login?next=${encodeURIComponent(pathname)}`);
    }
    return null;
  }

  return (
    <div className="mx-auto flex min-h-screen max-w-5xl flex-col px-6">
      <header className="border-white/8 flex items-center justify-between gap-4 border-b py-5">
        <Link href="/app" className="flex items-center gap-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" width={24} height={24} />
          <span className="font-semibold">Notch Metrics</span>
        </Link>

        <nav className="flex items-center gap-1">
          {NAV.map((item) => {
            const active =
              item.href === "/app" ? pathname === item.href : pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`rounded-lg px-3 py-1.5 text-sm transition ${
                  active ? "bg-white/10 text-white" : "text-white/55 hover:text-white"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
          <button
            type="button"
            onClick={() => void signOut().then(() => window.location.replace("/"))}
            className="ml-2 rounded-lg px-3 py-1.5 text-sm text-white/55 transition hover:text-white"
          >
            Sign out
          </button>
        </nav>
      </header>

      <main className="flex-1 py-10">{children}</main>
    </div>
  );
}
