import Link from "next/link";
import { ConnectorGrid } from "@/components/marketing/ConnectorGrid";
import { DownloadButton } from "@/components/marketing/DownloadButton";
import { NotchMockup } from "@/components/marketing/NotchMockup";
import { SectionIcon } from "@/components/marketing/SectionIcon";
import {
  ArrowRight,
  ChipIcon,
  CursorIcon,
  GridIcon,
  KeyIcon,
  LinkIcon,
  ListIcon,
  MoonIcon,
  NotchIcon,
  RefreshIcon,
  ShieldIcon,
  SparkIcon,
  TerminalIcon,
} from "@/components/marketing/icons";
import { LIVE_CONNECTORS } from "@/lib/connectors";

const ASSETS = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

/**
 * The version under the download button, from the same manifest the button
 * redirects to. Absent rather than wrong when the mirror cannot be reached:
 * a page that says v0.3 while the button hands out v0.4 is the one thing
 * this line must never do.
 */
async function latestVersion(): Promise<string | null> {
  try {
    const response = await fetch(`${ASSETS}/desktop/latest.json`, { next: { revalidate: 300 } });
    if (!response.ok) return null;
    const body = (await response.json()) as { version?: unknown };
    return typeof body.version === "string" ? body.version : null;
  } catch {
    return null;
  }
}

export default async function Home() {
  const version = await latestVersion();

  return (
    <main className="relative">
      {/* Hero */}
      <section className="relative isolate px-6 pb-16 pt-32 sm:pt-40">
        <div className="hero-glow" />

        <div className="mx-auto flex max-w-3xl flex-col items-center text-center">
          <Link
            href="#integrations"
            className="group flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] py-1 pl-1 pr-3 text-[13px] text-white/70 transition hover:bg-white/[0.07] hover:text-white"
          >
            <span className="brand-gradient rounded-full px-2.5 py-0.5 text-[11px] font-semibold text-black">
              New
            </span>
            Polar, Paddle and RevenueCat
            <ArrowRight className="h-3.5 w-3.5 transition group-hover:translate-x-0.5" />
          </Link>

          <h1 className="mt-8 text-balance text-[2.75rem] font-semibold leading-[1.02] tracking-tight sm:text-6xl">
            The dashboard you
            <br />
            never have to <span className="accent">open</span>
          </h1>

          <p className="mt-6 max-w-xl text-pretty text-lg leading-relaxed text-white/60">
            Revenue, MRR and subscribers from Stripe, Polar, Paddle and more, living in your
            MacBook&rsquo;s notch. Hover to look. Move away and it&rsquo;s gone.
          </p>

          <div className="mt-9 flex flex-col items-center gap-4">
            <DownloadButton size="lg" />
            <p className="font-mono text-[11px] tracking-wide text-white/40">
              {version ? `v${version} · ` : ""}Apple silicon · macOS 14+ · 7-day free trial
            </p>
          </div>
        </div>

        <div className="mx-auto mt-16 max-w-4xl sm:mt-20">
          <NotchMockup />
        </div>
      </section>

      {/* Three promises */}
      <section className="mx-auto grid max-w-4xl gap-10 px-6 py-16 sm:grid-cols-3 sm:py-20">
        <Pillar icon={<NotchIcon />}>
          No dock icon.
          <br />
          No menu bar clutter.
        </Pillar>
        <Pillar icon={<CursorIcon />}>
          Hover to look.
          <br />
          Move away, it&rsquo;s gone.
        </Pillar>
        <Pillar icon={<KeyIcon />}>
          Your API keys
          <br />
          never touch your Mac.
        </Pillar>
      </section>

      {/* Lives in the notch */}
      <Section
        icon={<NotchIcon />}
        title={
          <>
            Lives where you&rsquo;re <span className="accent">already</span> looking
          </>
        }
        lede="The notch is a few hundred pixels of glass that every Mac app pretends is not there. Notch Metrics makes it the one place your numbers wait for you."
      >
        <div className="panel overflow-hidden">
          <div className="p-3 sm:p-4">
            <NotchMockup variant="collapsed" />
          </div>
          <div className="grid gap-8 px-8 pb-10 pt-6 sm:grid-cols-3">
            <Feature icon={<CursorIcon />} title="Opens on hover">
              Rest the pointer on the camera housing and the notch expands over whatever you are
              doing. Leave, and it folds back to the shape it had.
            </Feature>
            <Feature icon={<GridIcon />} title="Four tile sizes">
              Widgets go from a single square up to the full width. Drag to arrange them and resize
              them in place, in the notch itself.
            </Feature>
            <Feature icon={<ListIcon />} title="Lists, not only numbers">
              A recent-payments feed sits beside the headline figures, so you see who just paid
              without opening a dashboard.
            </Feature>
          </div>
        </div>
      </Section>

      {/* Connect once */}
      <Section
        id="integrations"
        icon={<LinkIcon />}
        title={
          <>
            Connect once, <span className="accent">on the web</span>
          </>
        }
        lede={`Sign in, paste a key or approve an OAuth prompt, and every Mac you own picks it up. ${LIVE_CONNECTORS.length} connectors today, with more arriving without an app update.`}
      >
        <div className="panel px-6 py-10 sm:px-10">
          <ConnectorGrid />
        </div>

        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          <SecurityCard icon={<ShieldIcon />} title="Encrypted per integration">
            Each key is sealed with its own key, bound to your account and the provider. A row
            copied anywhere else does not decrypt.
          </SecurityCard>
          <SecurityCard icon={<KeyIcon />} title="The app sees a number">
            Our server talks to Stripe and hands your Mac a normalised series. The Mac app never
            holds a provider key.
          </SecurityCard>
          <SecurityCard icon={<RefreshIcon />} title="Disconnect means gone">
            Remove an integration and its encrypted key is deleted with it. There is no copy
            anywhere else to clean up.
          </SecurityCard>
        </div>
      </Section>

      {/* Custom metrics */}
      <Section
        icon={<TerminalIcon />}
        title={
          <>
            Your agent can <span className="accent">add</span> metrics
          </>
        }
        lede="A number we do not have a connector for is one prompt away. The MCP server lets Claude Code, or any MCP client, write a custom metric against any API."
      >
        <div className="grid gap-4 lg:grid-cols-[1.25fr_1fr]">
          <div className="panel overflow-hidden">
            <div className="flex items-center gap-1.5 border-b border-white/[0.06] px-4 py-3">
              <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
              <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
              <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
              <span className="ml-3 font-mono text-[11px] text-white/35">claude</span>
            </div>
            <div className="flex flex-col gap-5 p-5 font-mono text-[12.5px] leading-relaxed sm:p-6">
              <p className="text-white/45">
                <span className="text-white/25">$ </span>claude mcp add notch-metrics -- npx -y
                notch-metrics-mcp
              </p>
              <p className="rounded-xl bg-white/[0.05] px-4 py-3 font-sans text-[14px] text-white/85">
                Add a widget with the number of open issues on acme/app. Refresh it every ten
                minutes.
              </p>
              <div className="flex flex-col gap-1.5 text-white/55">
                <p>
                  <span className="text-emerald-400">✓</span> describe_runtime
                </p>
                <p>
                  <span className="text-emerald-400">✓</span> set_metric_secret{" "}
                  <span className="text-white/35">GITHUB_TOKEN → Keychain</span>
                </p>
                <p>
                  <span className="text-emerald-400">✓</span> test_metric{" "}
                  <span className="text-white/35">→ 14 · 412 ms · 1 request to api.github.com</span>
                </p>
                <p>
                  <span className="text-emerald-400">✓</span> create_metric{" "}
                  <span className="text-white/35">open_issues</span>
                </p>
              </div>
              <p className="text-white/85">
                Done. Enable &ldquo;Open issues&rdquo; from the widget gallery to show it in the
                notch.
              </p>
            </div>
          </div>

          <div className="flex flex-col gap-4">
            <SecurityCard icon={<ChipIcon />} title="Runs on your Mac">
              A metric is one file in Application Support, run by a runner built into the app. No
              Node install, nothing uploaded.
            </SecurityCard>
            <SecurityCard icon={<KeyIcon />} title="Keys stay in the Keychain">
              Secrets are declared, stored by macOS and handed to the runner over stdin. A metric
              with a key written into it is refused.
            </SecurityCard>
            <SecurityCard icon={<ShieldIcon />} title="Contained, not sandboxed">
              Each metric names the hosts it may call, and nothing else is reachable. It still runs
              as you, like a script you wrote. Read what your agent writes.
            </SecurityCard>
          </div>
        </div>
      </Section>

      {/* Designed for the Mac */}
      <section className="mx-auto max-w-5xl px-6 pt-28">
        <div className="relative overflow-hidden rounded-[32px] border border-white/[0.08] px-6 py-20 text-center sm:py-24">
          <div
            aria-hidden
            className="absolute inset-0 -z-10"
            style={{
              background:
                "radial-gradient(70% 60% at 50% 110%, rgba(216,25,194,0.35), transparent 70%), radial-gradient(50% 40% at 80% 0%, rgba(255,193,7,0.18), transparent 70%), #0b0a0e",
            }}
          />
          <div className="mx-auto flex items-center justify-center gap-3">
            {[<SparkIcon key="a" />, <ChipIcon key="b" />, <MoonIcon key="c" />].map(
              (icon, index) => (
                <span
                  key={index}
                  className={`flex items-center justify-center rounded-2xl border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-6 [&>svg]:w-6 ${
                    index === 1 ? "h-16 w-16 scale-110 bg-white/[0.09] text-white" : "h-12 w-12"
                  }`}
                >
                  {icon}
                </span>
              ),
            )}
          </div>
          <p className="eyebrow mt-10">Designed for</p>
          <h2 className="mt-2 text-5xl text-white sm:text-6xl">
            <span className="accent">The Mac</span>
          </h2>
          <p className="mx-auto mt-6 max-w-xl text-pretty text-white/60">
            Native Swift, built for Apple silicon. Signed, notarised, and updated in place. Every
            update is checked against both its hash and its Developer ID signature before it is
            installed. No Electron, no browser engine, no dock icon.
          </p>
          <div className="mt-10 flex justify-center">
            <DownloadButton size="lg" />
          </div>
        </div>
      </section>
    </main>
  );
}

function Section({
  id,
  icon,
  title,
  lede,
  children,
}: {
  id?: string;
  icon: React.ReactNode;
  title: React.ReactNode;
  lede: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="mx-auto max-w-5xl scroll-mt-28 px-6 pt-28">
      <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <SectionIcon>{icon}</SectionIcon>
        <h2 className="mt-8 text-balance text-4xl font-semibold leading-[1.08] tracking-tight sm:text-[2.75rem]">
          {title}
        </h2>
        <p className="mt-5 max-w-xl text-pretty text-[17px] leading-relaxed text-white/55">
          {lede}
        </p>
      </div>
      <div className="mt-12">{children}</div>
    </section>
  );
}

function Pillar({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <span className="flex h-11 w-11 items-center justify-center rounded-xl border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <p className="text-[15px] leading-snug text-white/80">{children}</p>
    </div>
  );
}

function Feature({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-3 text-center">
      <span className="flex h-10 w-10 items-center justify-center rounded-xl border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-5 [&>svg]:w-5">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-pretty text-sm leading-relaxed text-white/50">{children}</p>
    </div>
  );
}

function SecurityCard({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="panel flex flex-col gap-3 p-6">
      <span className="flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/[0.05] text-white/80 [&>svg]:h-[18px] [&>svg]:w-[18px]">
        {icon}
      </span>
      <h3 className="text-[15px] font-medium">{title}</h3>
      <p className="text-pretty text-sm leading-relaxed text-white/50">{children}</p>
    </div>
  );
}
