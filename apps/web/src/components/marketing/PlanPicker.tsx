"use client";

import { useState } from "react";
import { PLANS, annualSavingPercent, formatPrice } from "@notch/schemas";
import { ApiError, api } from "@/lib/api";
import { useSession } from "@/lib/auth-client";

/**
 * The two cards and the checkout call. Split from the page so the copy and
 * the FAQ render on the server and only this needs the session.
 */
export function PlanPicker() {
  const { data: session } = useSession();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  async function choose(plan: "pro" | "pro_annual") {
    if (!session) {
      window.location.href = `/login?next=${encodeURIComponent("/#pricing")}`;
      return;
    }
    setBusy(plan);
    setProblem(null);
    try {
      const { url } = await api<{ url: string }>("/v1/billing/checkout", {
        method: "POST",
        body: JSON.stringify({ plan }),
      });
      window.location.href = url;
    } catch (error) {
      setProblem(
        error instanceof ApiError && error.status === 503
          ? "Checkout is not switched on yet. Try again shortly."
          : error instanceof ApiError
            ? error.message
            : "We could not start checkout.",
      );
      setBusy(null);
    }
  }

  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <PlanCard
          title="Monthly"
          price={formatPrice(PLANS.pro.amount, "USD")}
          cadence="per month"
          note="Cancel whenever you like."
          aside="One coffee a month."
          asideIcon={<CoffeeGlyph />}
          busy={busy === "pro"}
          disabled={busy !== null}
          onChoose={() => void choose("pro")}
        />
        <PlanCard
          title="Yearly"
          price={formatPrice(PLANS.pro_annual.amount, "USD")}
          cadence="per year"
          was={formatPrice(PLANS.pro.amount * 12, "USD")}
          note={`${formatPrice(Math.round(PLANS.pro_annual.amount / 12), "USD")} a month, billed once.`}
          aside="Best value for money."
          asideIcon={<TagGlyph />}
          badge={`Save ${annualSavingPercent()}%`}
          highlighted
          busy={busy === "pro_annual"}
          disabled={busy !== null}
          onChoose={() => void choose("pro_annual")}
        />
      </div>

      {problem && (
        <p className="mt-6 rounded-xl border border-red-500/25 bg-red-500/10 px-4 py-3 text-center text-sm text-red-700">
          {problem}
        </p>
      )}
    </>
  );
}

function PlanCard({
  title,
  price,
  cadence,
  was,
  note,
  aside,
  asideIcon,
  badge,
  highlighted,
  busy,
  disabled,
  onChoose,
}: {
  title: string;
  price: string;
  cadence: string;
  /** What twelve months would have cost, shown struck through beside the price. */
  was?: string;
  note: string;
  /** The price in something the reader already buys. */
  aside?: string;
  asideIcon?: React.ReactNode;
  badge?: string;
  highlighted?: boolean;
  busy: boolean;
  disabled: boolean;
  onChoose: () => void;
}) {
  return (
    /* The yearly card is the brand's amber, flat. The site has one accent
       and this is the one place it is worth spending it: the card a reader
       is meant to pick should not be the same white as the one beside it. */
    <section
      className={`relative flex flex-col rounded-[28px] p-7 ${
        highlighted
          ? "bg-brand shadow-[0_30px_80px_-30px_rgba(255,193,7,0.7)]"
          : "border-ink/[0.08] border bg-white"
      }`}
    >
      {badge && (
        <span className="bg-ink absolute -top-3.5 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full px-3.5 py-1.5 text-xs font-semibold text-white">
          {badge}
        </span>
      )}
      <h2 className={`text-sm font-medium ${highlighted ? "text-ink/70" : "text-ink/60"}`}>
        {title}
      </h2>
      <p className="mt-3 flex items-baseline gap-2">
        {was && (
          <span
            className={`text-2xl font-medium tracking-tight line-through decoration-2 ${
              highlighted ? "text-ink/40 decoration-ink/45" : "text-ink/35 decoration-ink/40"
            }`}
          >
            {was}
          </span>
        )}
        <span className="text-5xl font-semibold tracking-tight">{price}</span>
        <span className={`text-sm ${highlighted ? "text-ink/60" : "text-ink/50"}`}>{cadence}</span>
      </p>
      <p className={`mt-2 pb-8 text-sm ${highlighted ? "text-ink/60" : "text-ink/45"}`}>{note}</p>
      {aside && (
        <p
          className={`-mt-4 mb-8 flex w-fit items-center gap-2 rounded-full py-1.5 pl-2.5 pr-3.5 text-[13px] font-medium ${
            highlighted ? "bg-ink/10 text-ink/75" : "bg-ink/[0.05] text-ink/60"
          }`}
        >
          {asideIcon}
          {aside}
        </p>
      )}
      <button
        type="button"
        onClick={onChoose}
        disabled={disabled}
        className={`mt-auto h-11 w-full shrink-0 rounded-full text-sm font-semibold transition disabled:opacity-50 ${
          highlighted
            ? "bg-ink hover:bg-ink/85 text-white"
            : "border-ink/15 text-ink hover:bg-ink/5 border"
        }`}
      >
        {busy ? "Opening checkout…" : "Start free trial"}
      </button>
    </section>
  );
}

/**
 * The cup beside the monthly price. Ink, with the steam in the one accent
 * the site has, so it reads as a drawing rather than as a second brand.
 */
function CoffeeGlyph() {
  return (
    <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <path
        d="M8 2.5c-.6 1 -.6 1.8 0 2.8M12 2c-.7 1.2 -.7 2.2 0 3.4M16 2.5c-.6 1 -.6 1.8 0 2.8"
        stroke="#ffc107"
        strokeWidth="1.6"
        strokeLinecap="round"
      />
      <path d="M4.5 9h13v5.5a5 5 0 0 1-5 5h-3a5 5 0 0 1-5-5V9Z" fill="currentColor" />
      <path
        d="M17.5 10.5h1.25a2.25 2.25 0 0 1 0 4.5H17.5"
        stroke="currentColor"
        strokeWidth="1.6"
      />
    </svg>
  );
}

/** The tag beside the yearly price, in the one accent the site has. */
function TagGlyph() {
  return (
    <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <path
        d="M11.6 2.8 3.2 11.2a2 2 0 0 0 0 2.8l6.8 6.8a2 2 0 0 0 2.8 0l8.4-8.4V2.8h-9.6Z"
        fill="currentColor"
      />
      <circle cx="17" cy="7" r="1.9" fill="#fff" />
    </svg>
  );
}
