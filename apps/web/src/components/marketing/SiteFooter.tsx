import Link from "next/link";

const COLUMNS: { title: string; links: { href: string; label: string; external?: boolean }[] }[] = [
  {
    title: "Product",
    links: [
      { href: "/download", label: "Download" },
      { href: "/#pricing", label: "Pricing" },
      { href: "/sources", label: "Sources" },
      { href: "/login", label: "Sign in" },
    ],
  },
  {
    title: "Resources",
    links: [
      { href: "/blog", label: "Blog" },
      { href: "/free-tools", label: "Free tools" },
      { href: "/library", label: "Content library" },
    ],
  },
  {
    title: "Developers",
    links: [
      {
        href: "https://www.npmjs.com/package/notch-metrics-mcp",
        label: "MCP server",
        external: true,
      },
    ],
  },
  {
    title: "Company",
    links: [
      { href: "/privacy", label: "Privacy" },
      { href: "/terms", label: "Terms" },
      { href: "/security", label: "Security" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="relative mt-32 overflow-hidden border-t border-white/[0.06]">
      <div className="mx-auto grid max-w-6xl gap-12 px-6 pb-10 pt-16 sm:grid-cols-[1.4fr_repeat(4,1fr)]">
        <div className="flex flex-col gap-4">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="Notch Metrics" width={28} height={28} />
          <p className="max-w-[16rem] text-sm leading-relaxed text-white/40">
            Your business metrics, in the MacBook notch. Built for Apple silicon, macOS 14 and
            later.
          </p>
          <p className="text-xs text-white/30">© {new Date().getFullYear()} Notch Metrics</p>
        </div>

        {COLUMNS.map((column) => (
          <div key={column.title}>
            <h3 className="text-sm font-medium text-white/70">{column.title}</h3>
            <ul className="mt-4 flex flex-col gap-2.5">
              {column.links.map((link) => (
                <li key={link.href}>
                  <Link
                    href={link.href}
                    target={link.external ? "_blank" : undefined}
                    rel={link.external ? "noreferrer" : undefined}
                    className="text-sm text-white/45 transition hover:text-white"
                  >
                    {link.label}
                    {link.external && <span aria-hidden> ↗</span>}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div aria-hidden className="mx-auto max-w-6xl px-6">
        <div className="h-[0.42em] overflow-hidden text-[clamp(2.75rem,10.2vw,9rem)]">
          <span className="wordmark block whitespace-nowrap">NOTCH METRICS</span>
        </div>
      </div>
    </footer>
  );
}
