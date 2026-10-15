"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { signOut, useSession } from "@/lib/auth-client";

type Icon = (props: { className?: string }) => React.ReactElement;

const NAV: { href: string; label: string; icon: Icon }[] = [
  { href: "/app", label: "Overview", icon: OverviewIcon },
  { href: "/app/integrations", label: "Integrations", icon: IntegrationsIcon },
  { href: "/app/settings/billing", label: "Billing", icon: BillingIcon },
];

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { data: session, isPending } = useSession();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  // The sidebar is an overlay on narrow screens. Close it on navigation so a
  // tap on a nav item does not leave the overlay covering the page it chose.
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // A client-side guard, not a security boundary — every route this page
  // calls is authorised on the Worker. This only avoids rendering a shell
  // full of empty states to somebody who is simply signed out.
  if (!isPending && !session) {
    if (typeof window !== "undefined") {
      window.location.replace(`/login?next=${encodeURIComponent(pathname)}`);
    }
    return null;
  }

  const user = session?.user;
  const displayName = user?.name?.trim() || user?.email || "Account";

  return (
    <div className="dark-surface flex min-h-screen">
      {open && (
        <button
          type="button"
          aria-label="Close navigation"
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-30 bg-black/60 md:hidden"
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-60 shrink-0 flex-col border-r border-white/[0.06] bg-white/[0.025] transition-transform md:translate-x-0 ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="flex h-14 items-center px-3">
          <Link
            href="/app"
            className="flex min-w-0 items-center gap-2 rounded-md px-2 py-1.5 transition hover:bg-white/[0.06]"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.svg" alt="" width={20} height={20} />
            <span className="truncate text-sm font-semibold">Notch Metrics</span>
          </Link>
        </div>

        <nav className="flex flex-1 flex-col gap-0.5 px-3">
          {NAV.map((item) => {
            const active =
              item.href === "/app" ? pathname === item.href : pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex items-center gap-2.5 rounded-md px-2 py-1.5 text-sm transition ${
                  active
                    ? "bg-white/[0.06] text-white"
                    : "text-white/60 hover:bg-white/[0.03] hover:text-white"
                }`}
              >
                <item.icon
                  className={`size-4 shrink-0 ${active ? "text-white" : "text-white/45"}`}
                />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="border-t border-white/[0.06] p-3">
          <div className="flex items-center gap-2.5 px-2 py-1.5">
            <Avatar name={displayName} image={user?.image ?? null} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm">{displayName}</p>
              {user?.email && user.name && (
                <p className="truncate text-xs text-white/45">{user.email}</p>
              )}
            </div>
            <button
              type="button"
              title="Sign out"
              aria-label="Sign out"
              onClick={() => void signOut().then(() => window.location.replace("/"))}
              className="rounded-md p-1.5 text-white/45 transition hover:bg-white/[0.06] hover:text-white"
            >
              <SignOutIcon className="size-4" />
            </button>
          </div>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col md:pl-60">
        <header className="flex h-14 items-center gap-3 border-b border-white/[0.06] px-4 md:hidden">
          <button
            type="button"
            aria-label="Open navigation"
            onClick={() => setOpen(true)}
            className="rounded-md p-1.5 text-white/60 transition hover:bg-white/[0.06] hover:text-white"
          >
            <MenuIcon className="size-5" />
          </button>
          <span className="text-sm font-semibold">Notch Metrics</span>
        </header>

        <main className="flex-1 px-6 py-10 md:px-10">
          <div className="mx-auto max-w-4xl">{children}</div>
        </main>
      </div>
    </div>
  );
}

function Avatar({ name, image }: { name: string; image: string | null }) {
  if (image) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={image} alt="" className="size-6 shrink-0 rounded-full object-cover" />;
  }
  return (
    <span className="brand-gradient flex size-6 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold text-white">
      {name.charAt(0).toUpperCase()}
    </span>
  );
}

// Stroked 16px glyphs in the Linear idiom. Inline rather than an icon package:
// three icons do not justify a dependency, and inline SVG picks up
// `currentColor` from the nav item's text colour with no extra wiring.
function OverviewIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
    >
      <rect x="2" y="2" width="5" height="5" rx="1.25" />
      <rect x="9" y="2" width="5" height="5" rx="1.25" />
      <rect x="2" y="9" width="5" height="5" rx="1.25" />
      <rect x="9" y="9" width="5" height="5" rx="1.25" />
    </svg>
  );
}

function IntegrationsIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
    >
      <path d="M6 2v3M10 2v3" strokeLinecap="round" />
      <path d="M3.5 5h9v2.5a4.5 4.5 0 0 1-9 0V5Z" strokeLinejoin="round" />
      <path d="M8 12v2.5" strokeLinecap="round" />
    </svg>
  );
}

function BillingIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
    >
      <rect x="1.75" y="3.25" width="12.5" height="9.5" rx="1.75" />
      <path d="M1.75 6.5h12.5" />
      <path d="M4.5 10h3" strokeLinecap="round" />
    </svg>
  );
}

function SignOutIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
    >
      <path d="M6.5 2.5H4a1.5 1.5 0 0 0-1.5 1.5v8A1.5 1.5 0 0 0 4 13.5h2.5" strokeLinecap="round" />
      <path d="M10 5l3 3-3 3M13 8H6.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function MenuIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
    >
      <path d="M2.5 4.5h11M2.5 8h11M2.5 11.5h11" strokeLinecap="round" />
    </svg>
  );
}
