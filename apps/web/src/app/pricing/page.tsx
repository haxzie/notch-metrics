"use client";

import { useState } from "react";
import { PLANS, annualSavingPercent, formatPrice } from "@notch/schemas";
import { ApiError, api } from "@/lib/api";
import { useSession } from "@/lib/auth-client";

const INCLUDED = [
  "Every integration we support, with no per-connector charge",
  "Unlimited widgets in the notch and in list view",
  "Custom metrics authored by your own coding agent over MCP",
  "Layout synced as a backup across your Macs",
];

export default function Pricing() {
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
    <main className="mx-auto max-w-3xl px-6 py-20">
      <header className="text-center">
        <h1 className="text-4xl font-semibold tracking-tight">One plan. Both billing cycles.</h1>
        <p className="mt-3 text-white/60">
          Seven days free, no card. After that it is {formatPrice(PLANS.pro.amount, "USD")} a month
          — or {formatPrice(PLANS.pro_annual.amount, "USD")} a year and save {annualSavingPercent()}
          %.
        </p>
      </header>

      <div className="mt-12 grid gap-5 sm:grid-cols-2">
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
          note={`Works out at ${formatPrice(Math.round(PLANS.pro_annual.amount / 12), "USD")} a month.`}
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

      <ul className="mx-auto mt-12 grid max-w-xl gap-3 text-sm text-white/70">
        {INCLUDED.map((item) => (
          <li key={item} className="flex gap-3">
            <span aria-hidden className="text-white/30">
              —
            </span>
            {item}
          </li>
        ))}
      </ul>
    </main>
  );
}

function PlanCard({
  title,
  price,
  cadence,
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
  note: string;
  badge?: string;
  highlighted?: boolean;
  busy: boolean;
  disabled: boolean;
  onChoose: () => void;
}) {
  return (
    <section
      className={`relative rounded-2xl border p-6 ${
        highlighted ? "border-white/25 bg-white/[0.06]" : "border-white/10 bg-white/[0.02]"
      }`}
    >
      {badge && (
        <span className="brand-gradient absolute -top-2.5 right-5 rounded-full px-2.5 py-0.5 text-xs font-semibold text-black">
          {badge}
        </span>
      )}
      <h2 className="text-sm font-medium text-white/60">{title}</h2>
      <p className="mt-2 flex items-baseline gap-1.5">
        <span className="text-4xl font-semibold tracking-tight">{price}</span>
        <span className="text-sm text-white/50">{cadence}</span>
      </p>
      <p className="mt-1 text-sm text-white/45">{note}</p>
      <button
        type="button"
        onClick={onChoose}
        disabled={disabled}
        className={`mt-6 w-full rounded-xl px-4 py-2.5 text-sm font-semibold transition disabled:opacity-50 ${
          highlighted
            ? "brand-gradient text-black"
            : "border border-white/15 text-white hover:bg-white/5"
        }`}
      >
        {busy ? "Opening checkout…" : "Start free trial"}
      </button>
    </section>
  );
}
