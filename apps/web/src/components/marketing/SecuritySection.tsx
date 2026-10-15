import Link from "next/link";
import { ConnectorMark } from "@/components/ConnectorMark";

/**
 * How a provider key is held, with a drawing of each claim.
 *
 * On its own grey band because it is the section a careful reader comes
 * looking for, and because three white cards on white paper read as small
 * print rather than as the answer to "where does my Stripe key live".
 */
export function SecuritySection() {
  return (
    <section id="security" className="mx-auto max-w-6xl scroll-mt-28 px-6 pt-28">
      <div className="bg-ink/[0.035] rounded-[40px] px-6 py-16 sm:px-12 sm:py-20">
        <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
          <h2 className="text-balance text-[2.5rem] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[3.25rem]">
            Every key encrypted, and sealed to your account
          </h2>
          <p className="text-ink/55 mt-5 max-w-xl text-pretty text-[17px] leading-relaxed">
            A provider key is encrypted the moment you paste it, with a key of its own. It stays on
            the server, where no app on your Mac can read it.
          </p>
        </div>

        <div className="mt-12 grid gap-4 sm:grid-cols-3">
          <Card
            title="Encrypted with its own key"
            body="Your account, the integration and the provider are bound into the encryption. A row copied anywhere else decrypts to nothing."
            tint="rgba(99,91,255,0.12)"
          >
            <Sealing />
          </Card>
          <Card
            title="No app on your Mac can read it"
            body="The key never leaves the server. Notch Metrics calls Stripe for you and hands your Mac a number, which is all any app on it could find."
            tint="rgba(255,193,7,0.2)"
          >
            <Isolated />
          </Card>
          <Card
            title="Disconnect deletes it"
            body="Remove an integration and its encrypted key goes with it. There is no second copy anywhere to clean up."
            tint="rgba(242,84,91,0.12)"
          >
            <Deleted />
          </Card>
        </div>

        <p className="text-ink/45 mt-8 text-center text-sm">
          <Link
            href="/security"
            className="hover:text-ink underline-offset-4 transition hover:underline"
          >
            How Notch Metrics handles your keys
          </Link>
        </p>
      </div>
    </section>
  );
}

function Card({
  title,
  body,
  tint,
  children,
}: {
  title: string;
  body: string;
  /** A flat wash behind the drawing. Colour makes the three cards read as
      three steps rather than as one grey block. */
  tint: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col rounded-[28px] bg-white p-5 shadow-[0_1px_2px_rgba(11,10,14,0.04),0_18px_40px_-28px_rgba(11,10,14,0.2)] sm:p-6">
      <div
        className="flex h-[132px] items-center justify-center rounded-[20px] px-4"
        style={{ background: tint }}
      >
        {children}
      </div>
      <h3 className="mt-6 text-[17px] font-semibold tracking-tight">{title}</h3>
      <p className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">{body}</p>
    </div>
  );
}

/** The key as you type it, and the key as it is stored. */
function Sealing() {
  return (
    <div className="flex w-full max-w-[220px] flex-col items-center gap-1.5">
      {/* The key being sealed is a Stripe key, so it is drawn as one. */}
      <span className="text-ink/55 flex w-full items-center gap-2 rounded-lg bg-white px-2.5 py-2 font-mono text-[11px] shadow-[0_1px_2px_rgba(11,10,14,0.06)]">
        <ConnectorMark id="stripe" name="Stripe" accentColor="#635BFF" size={18} />
        sk_live_4eC39H…
      </span>
      <ArrowDown />
      <span className="bg-ink flex w-full items-center gap-2 rounded-lg px-2.5 py-2 font-mono text-[11px] text-white/80">
        <span className="text-brand">
          <LockGlyph />
        </span>
        9f2a b741 c0de 55e1
      </span>
    </div>
  );
}

/** The key on the server, with every app on the Mac on the other side. */
function Isolated() {
  return (
    <div className="flex items-center gap-3">
      <span className="bg-ink flex h-[54px] w-[54px] flex-col items-center justify-center gap-1 rounded-[16px]">
        <span className="text-brand">
          <LockGlyph large />
        </span>
        <span className="text-[8px] font-medium uppercase tracking-wider text-white/50">
          Server
        </span>
      </span>
      {/* The wall. Dashed, because nothing crosses it. */}
      <span className="border-ink/25 h-[64px] border-l-2 border-dashed" />
      {/* Any three apps on the Mac, in app colours. Not connectors: these are
          the things that cannot reach the key. */}
      <span className="flex items-center gap-1.5">
        {["#635BFF", "#2DB55D", "#1F8DED"].map((colour) => (
          <span
            key={colour}
            className="squircle h-8 w-8 opacity-80"
            style={{ backgroundColor: colour }}
          />
        ))}
      </span>
    </div>
  );
}

/** The same stored key, on its way out. */
function Deleted() {
  return (
    <div className="flex w-full max-w-[220px] flex-col items-center gap-2">
      <span className="bg-ink/15 text-ink/35 flex w-full items-center gap-2 rounded-lg px-2.5 py-2 font-mono text-[11px] line-through">
        <LockGlyph />
        9f2a b741 c0de 55e1
      </span>
      <span className="flex items-center gap-1.5 text-[11px] font-medium text-[#c4323a]">
        <BinGlyph />
        Deleted with the integration
      </span>
    </div>
  );
}

function LockGlyph({ large }: { large?: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={`${large ? "h-5 w-5" : "h-3.5 w-3.5"} shrink-0`}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <rect x="4.5" y="10" width="15" height="10" rx="3" />
      <path d="M8 10V7.5a4 4 0 0 1 8 0V10" />
    </svg>
  );
}

function ArrowDown() {
  return (
    <svg
      viewBox="0 0 24 24"
      className="text-ink/30 h-4 w-4"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M12 4v16M6 14l6 6 6-6" />
    </svg>
  );
}

function BinGlyph() {
  return (
    <svg
      viewBox="0 0 24 24"
      className="h-3.5 w-3.5"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M4 7h16M10 7V5h4v2M6.5 7l.8 12.2a1.8 1.8 0 0 0 1.8 1.8h5.8a1.8 1.8 0 0 0 1.8-1.8L17.5 7" />
    </svg>
  );
}
