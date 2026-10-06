"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { BillingState, Integration } from "@notch/schemas";
import { api } from "@/lib/api";

export default function Overview() {
  const [integrations, setIntegrations] = useState<Integration[] | null>(null);
  const [billing, setBilling] = useState<BillingState | null>(null);

  useEffect(() => {
    // Settled rather than awaited in sequence: a billing failure should not
    // blank the integration count, and vice versa.
    void Promise.allSettled([
      api<Integration[]>("/v1/integrations"),
      api<BillingState>("/v1/billing"),
    ]).then(([list, state]) => {
      if (list.status === "fulfilled") setIntegrations(list.value);
      if (state.status === "fulfilled") setBilling(state.value);
    });
  }, []);

  const failing = integrations?.filter((row) => row.status === "auth_failed") ?? [];

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Overview</h1>
        <p className="mt-1 text-sm text-white/55">
          The dashboard manages your account. The numbers live in the notch.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat
          label="Connected"
          value={integrations === null ? "—" : String(integrations.length)}
          hint={integrations === null ? "Loading" : "integrations"}
        />
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
        <Stat
          label="Needs attention"
          value={integrations === null ? "—" : String(failing.length)}
          hint={failing.length ? "reconnect required" : "everything healthy"}
        />
      </div>

      {failing.length > 0 && (
        <section className="bg-amber-500/8 rounded-xl border border-amber-500/25 p-5">
          <h2 className="font-medium">Some integrations stopped working</h2>
          <p className="mt-1 text-sm text-white/60">
            {failing.map((row) => row.label).join(", ")} rejected our last request. We stop polling
            after a failed key, so these need reconnecting before their widgets fill in again.
          </p>
          <Link
            href="/app/integrations"
            className="mt-3 inline-block rounded-lg border border-white/15 px-3 py-1.5 text-sm transition hover:bg-white/5"
          >
            Fix them
          </Link>
        </section>
      )}

      <section className="rounded-xl border border-white/10 p-5">
        <h2 className="font-medium">Get the app</h2>
        <p className="mt-1 text-sm text-white/60">
          Notch Metrics is a Mac app. This dashboard exists for the things a notch is a bad place
          for — connecting accounts and managing your subscription.
        </p>
        <a
          href="/download"
          className="brand-gradient mt-3 inline-block rounded-lg px-4 py-2 text-sm font-semibold text-black"
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
