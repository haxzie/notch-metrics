import Link from "next/link";

const features = [
  {
    title: "It lives in the notch",
    body: "No dock icon, no menu bar clutter. Hover the camera housing and your numbers are there; move away and the notch looks untouched.",
  },
  {
    title: "Connect once, on the web",
    body: "Stripe, Dodo Payments and Lemon Squeezy. Keys are encrypted per-integration and never leave the server — the Mac app only ever sees a normalised number.",
  },
  {
    title: "Your agent can add metrics",
    body: "An MCP server lets Claude Code write custom metrics against any API. They run on your machine, with your keys, in the Keychain.",
  },
];

export default function Home() {
  return (
    <main className="mx-auto flex max-w-5xl flex-col gap-24 px-6 py-20">
      <header className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-sm font-medium">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" width={22} height={22} />
          Notch Metrics
        </span>
        <nav className="flex items-center gap-6 text-sm text-white/60">
          <Link href="/pricing" className="hover:text-white">
            Pricing
          </Link>
          <Link href="/docs" className="hover:text-white">
            Docs
          </Link>
          <Link href="/login" className="hover:text-white">
            Sign in
          </Link>
        </nav>
      </header>

      <section className="flex flex-col items-start gap-6">
        <h1 className="max-w-3xl text-5xl font-semibold leading-[1.05] tracking-tight sm:text-6xl">
          Your business, <span className="brand-text">in the notch</span>.
        </h1>
        <p className="max-w-xl text-lg text-white/60">
          Revenue, MRR and subscribers a glance away — in the one piece of screen that was doing
          nothing.
        </p>

        <div className="flex flex-wrap items-center gap-3">
          <Link
            href="/download"
            className="brand-gradient rounded-full px-6 py-3 text-sm font-semibold text-black transition hover:opacity-90"
          >
            Download for Mac
          </Link>
          <span className="text-sm text-white/40">Apple silicon · macOS 14+ · 7-day trial</span>
        </div>
      </section>

      <section className="grid gap-8 sm:grid-cols-3">
        {features.map((feature) => (
          <div key={feature.title} className="flex flex-col gap-2">
            <h2 className="text-base font-medium">{feature.title}</h2>
            <p className="text-sm leading-relaxed text-white/55">{feature.body}</p>
          </div>
        ))}
      </section>

      <footer className="flex flex-wrap items-center justify-between gap-4 border-t border-white/10 pt-8 text-sm text-white/40">
        <span>© {new Date().getFullYear()} Notch Metrics</span>
        <div className="flex gap-6">
          <Link href="/privacy" className="hover:text-white">
            Privacy
          </Link>
          <Link href="/terms" className="hover:text-white">
            Terms
          </Link>
          <Link href="/security" className="hover:text-white">
            Security
          </Link>
        </div>
      </footer>
    </main>
  );
}
