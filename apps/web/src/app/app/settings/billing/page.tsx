"use client";

import { useEffect, useState } from "react";
import { PLANS, annualSavingPercent, formatPrice, type BillingState } from "@notch/schemas";
import { ApiError, api } from "@/lib/api";

export default function Billing() {
  const [state, setState] = useState<BillingState | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    void api<BillingState>("/v1/billing")
      .then(setState)
      .catch(() => setProblem("We could not load your billing details."));
  }, []);

  async function go(path: string, key: string, body?: unknown) {
    setBusy(key);
    setProblem(null);
    try {
      const { url } = await api<{ url: string }>(path, {
        method: "POST",
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      window.location.href = url;
    } catch (error) {
      setProblem(
        error instanceof ApiError && error.status === 503
          ? "Billing is not switched on yet. Try again shortly."
          : error instanceof ApiError
            ? error.message
            : "Something went wrong.",
      );
      setBusy(null);
    }
  }

  const isPro = state?.plan === "pro" && state.status === "active";

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Billing</h1>
        <p className="mt-1 text-sm text-white/55">
          Seven days free, then {formatPrice(PLANS.pro.amount, "USD")} a month or{" "}
          {formatPrice(PLANS.pro_annual.amount, "USD")} a year.
        </p>
      </div>

      {problem && (
        <p className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-300">
          {problem}
        </p>
      )}

      <section className="rounded-xl border border-white/10 bg-white/[0.02] p-5">
        <p className="text-sm text-white/50">Current plan</p>
        <p className="mt-1 text-2xl font-semibold">{state === null ? "—" : planLabel(state)}</p>
        <p className="mt-1 text-sm text-white/45">{state === null ? "Loading…" : detail(state)}</p>

        {state?.hasCustomer && (
          <button
            type="button"
            onClick={() => void go("/v1/billing/portal", "portal")}
            disabled={busy !== null}
            className="mt-4 rounded-lg border border-white/15 px-4 py-2 text-sm transition hover:bg-white/5 disabled:opacity-50"
          >
            {busy === "portal" ? "Opening…" : "Manage payment and invoices"}
          </button>
        )}
      </section>

      {!isPro && (
        <section className="grid gap-4 sm:grid-cols-2">
          <Option
            title="Monthly"
            price={`${formatPrice(PLANS.pro.amount, "USD")} / month`}
            busy={busy === "pro"}
            disabled={busy !== null}
            onChoose={() => void go("/v1/billing/checkout", "pro", { plan: "pro" })}
          />
          <Option
            title="Yearly"
            price={`${formatPrice(PLANS.pro_annual.amount, "USD")} / year`}
            badge={`Save ${annualSavingPercent()}%`}
            highlighted
            busy={busy === "pro_annual"}
            disabled={busy !== null}
            onChoose={() => void go("/v1/billing/checkout", "pro_annual", { plan: "pro_annual" })}
          />
        </section>
      )}
    </div>
  );
}

function planLabel(state: BillingState): string {
  if (state.plan === "pro") return state.status === "active" ? "Pro" : `Pro (${state.status})`;
  if (state.plan === "trial") return "Free trial";
  return "No active plan";
}

function detail(state: BillingState): string {
  if (state.status === "trialing" && state.trialEndsAt) {
    return `Your trial runs until ${new Date(state.trialEndsAt).toLocaleDateString()}.`;
  }
  if (state.graceUntil && new Date(state.graceUntil) > new Date()) {
    return `A payment failed. Access continues until ${new Date(state.graceUntil).toLocaleDateString()}.`;
  }
  if (state.cancelAtPeriodEnd && state.currentPeriodEnd) {
    return `Cancels on ${new Date(state.currentPeriodEnd).toLocaleDateString()}.`;
  }
  if (state.currentPeriodEnd) {
    return `Renews on ${new Date(state.currentPeriodEnd).toLocaleDateString()}.`;
  }
  return "Pick a plan below to keep your metrics loading.";
}

function Option({
  title,
  price,
  badge,
  highlighted,
  busy,
  disabled,
  onChoose,
}: {
  title: string;
  price: string;
  badge?: string;
  highlighted?: boolean;
  busy: boolean;
  disabled: boolean;
  onChoose: () => void;
}) {
  return (
    <div
      className={`relative rounded-xl border p-5 ${
        highlighted ? "border-white/25 bg-white/[0.06]" : "border-white/10"
      }`}
    >
      {badge && (
        <span className="brand-gradient absolute -top-2.5 right-4 rounded-full px-2 py-0.5 text-xs font-semibold text-white">
          {badge}
        </span>
      )}
      <p className="text-sm text-white/50">{title}</p>
      <p className="mt-1 text-xl font-semibold">{price}</p>
      <button
        type="button"
        onClick={onChoose}
        disabled={disabled}
        className={`mt-4 w-full rounded-lg px-4 py-2 text-sm font-semibold transition disabled:opacity-50 ${
          highlighted ? "brand-gradient text-white" : "border border-white/15 hover:bg-white/5"
        }`}
      >
        {busy ? "Opening checkout…" : "Choose"}
      </button>
    </div>
  );
}
