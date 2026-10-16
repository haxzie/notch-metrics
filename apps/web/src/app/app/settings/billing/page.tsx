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
          <div className="mt-4">
            <button
              type="button"
              onClick={() => void go("/v1/billing/portal", "portal")}
              disabled={busy !== null}
              className="rounded-lg border border-white/15 px-4 py-2 text-sm transition hover:bg-white/5 disabled:opacity-50"
            >
              {busy === "portal" ? "Opening…" : "Manage subscription"}
            </button>
            <p className="mt-2 text-xs text-white/40">
              Update your card, download invoices, or cancel.
            </p>
          </div>
        )}

        {/* A paid plan with no customer behind it. Only a plan set by hand
            reaches this, and silently showing nothing leaves somebody with
            no way to cancel and no idea why. */}
        {state?.plan === "pro" && !state.hasCustomer && (
          <p className="mt-4 text-xs text-white/40">Manage this plan where you bought it.</p>
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

/** Whether the trial date on the account is still in the future. */
function trialLive(state: BillingState): boolean {
  return state.trialEndsAt !== null && new Date(state.trialEndsAt) > new Date();
}

function planLabel(state: BillingState): string {
  if (state.plan === "pro") return state.status === "active" ? "Pro" : `Pro (${state.status})`;
  // `plan` stays "trial" after the trial runs out, because nothing downgrades
  // the row. The date is what decides, here and on the server.
  if (state.plan === "trial") return trialLive(state) ? "Free trial" : "Trial ended";
  return "No active plan";
}

function detail(state: BillingState): string {
  if (state.trialEndsAt && !trialLive(state) && state.plan !== "pro") {
    return `Your trial ended on ${new Date(state.trialEndsAt).toLocaleDateString()}.`;
  }
  if (state.status === "trialing" && state.trialEndsAt) {
    return `Your trial runs until ${new Date(state.trialEndsAt).toLocaleDateString()}.`;
  }
  if (state.graceUntil && new Date(state.graceUntil) > new Date()) {
    return `A payment failed. Access continues until ${new Date(state.graceUntil).toLocaleDateString()}.`;
  }
  // Both of these come before the renewal line, and the status check is not
  // redundant. Dodo sets `cancel_at_next_billing_date` on some cancellations
  // and not others, so a cancelled plan could reach the line below and tell
  // somebody who had just cancelled that they would be charged again.
  if (state.status === "cancelled" && state.currentPeriodEnd) {
    return `Your plan ends on ${new Date(state.currentPeriodEnd).toLocaleDateString()}.`;
  }
  if (state.cancelAtPeriodEnd && state.currentPeriodEnd) {
    return `Cancels on ${new Date(state.currentPeriodEnd).toLocaleDateString()}.`;
  }
  if (state.status === "cancelled") return "Your plan is cancelled.";
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
