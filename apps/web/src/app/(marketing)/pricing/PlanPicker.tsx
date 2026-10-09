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
      window.location.href = `/login?next=${encodeURIComponent("/pricing")}`;
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
          badge={`Save ${annualSavingPercent()}%`}
          highlighted
          busy={busy === "pro_annual"}
          disabled={busy !== null}
          onChoose={() => void choose("pro_annual")}
        />
      </div>

      {problem && (
        <p className="mt-6 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-center text-sm text-red-300">
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
  badge?: string;
  highlighted?: boolean;
  busy: boolean;
  disabled: boolean;
  onChoose: () => void;
}) {
  return (
    <section
      className={`relative flex flex-col rounded-[28px] border p-7 ${
        highlighted
          ? "border-white/20 bg-white/[0.06] shadow-[0_30px_80px_-30px_rgba(216,25,194,0.45)]"
          : "border-white/[0.08] bg-white/[0.025]"
      }`}
    >
      {badge && (
        <span className="brand-gradient absolute -top-3 right-6 rounded-full px-3 py-1 text-xs font-semibold text-black">
          {badge}
        </span>
      )}
      <h2 className="text-sm font-medium text-white/60">{title}</h2>
      <p className="mt-3 flex items-baseline gap-2">
        {was && (
          <span className="text-2xl font-medium tracking-tight text-white/35 line-through decoration-white/40 decoration-2">
            {was}
          </span>
        )}
        <span className="text-5xl font-semibold tracking-tight">{price}</span>
        <span className="text-sm text-white/50">{cadence}</span>
      </p>
      <p className="mt-2 text-sm text-white/45">{note}</p>
      <button
        type="button"
        onClick={onChoose}
        disabled={disabled}
        className={`mt-8 h-11 w-full rounded-full text-sm font-semibold transition disabled:opacity-50 ${
          highlighted
            ? "bg-white text-black hover:bg-white/90"
            : "border border-white/15 text-white hover:bg-white/5"
        }`}
      >
        {busy ? "Opening checkout…" : "Start free trial"}
      </button>
    </section>
  );
}
