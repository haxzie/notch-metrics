"use client";

import { useEffect, useState } from "react";
import type { BillingState } from "@notch/schemas";
import { api } from "@/lib/api";

export default function Overview() {
  const [billing, setBilling] = useState<BillingState | null>(null);

  // Billing only. Connections are not the server's any more: a key is
  // entered in the notch and lives in that Mac's Keychain, so this dashboard
  // has no way to count them and no business knowing they exist.
  useEffect(() => {
    void api<BillingState>("/v1/billing")
      .then(setBilling)
      .catch(() => {});
  }, []);

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Overview</h1>
        <p className="mt-1 text-sm text-white/55">
          The dashboard manages your account. The numbers live in the notch.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Stat
          label="Plan"
          value={
            billing === null
              ? "—"
              : billing.plan === "pro"
                ? "Pro"
                : billing.plan === "trial"
                  ? "Trial"
                  : "Expired"
          }
          hint={describeBilling(billing)}
        />
      </div>

      <section className="rounded-xl border border-white/10 p-5">
        <h2 className="font-medium">Get the app</h2>
        <p className="mt-1 text-sm text-white/60">
          Notch Metrics is a Mac app. Accounts are connected in the notch, where the keys stay. This
          dashboard is for your subscription.
        </p>
        <a
          href="/download"
          className="brand-gradient mt-3 inline-block rounded-lg px-4 py-2 text-sm font-semibold text-white"
        >
          Download for macOS
        </a>
      </section>
    </div>
  );
}

function describeBilling(state: BillingState | null): string {
  if (!state) return "Loading";
  if (state.status === "trialing" && state.trialEndsAt) {
    const days = Math.max(
      0,
      Math.ceil((new Date(state.trialEndsAt).getTime() - Date.now()) / 86_400_000),
    );
    return days === 1 ? "1 day of trial left" : `${days} days of trial left`;
  }
  if (state.cancelAtPeriodEnd && state.currentPeriodEnd) {
    return `ends ${new Date(state.currentPeriodEnd).toLocaleDateString()}`;
  }
  if (state.currentPeriodEnd) {
    return `renews ${new Date(state.currentPeriodEnd).toLocaleDateString()}`;
  }
  return state.status;
}

function Stat({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.02] p-5">
      <p className="text-sm text-white/50">{label}</p>
      <p className="mt-1 text-3xl font-semibold tracking-tight">{value}</p>
      <p className="mt-1 text-xs text-white/40">{hint}</p>
    </div>
  );
}
