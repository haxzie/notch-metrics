"use client";

import { useCallback, useEffect, useState } from "react";
import type { Integration } from "@notch/schemas";
import { ApiError, api } from "@/lib/api";
import { ConnectorMark } from "@/components/ConnectorMark";

interface ConnectorEntry {
  id: string;
  name: string;
  tagline: string;
  accentColor: string;
  status: "stable" | "beta" | "coming_soon";
  authMode: "api_key" | "oauth2";
}

interface Catalogue {
  categories: { id: string; label: string; connectors: ConnectorEntry[] }[];
}

export default function Integrations() {
  const [catalogue, setCatalogue] = useState<Catalogue | null>(null);
  const [connected, setConnected] = useState<Integration[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const [cat, mine] = await Promise.allSettled([
      api<Catalogue>("/v1/connectors"),
      api<Integration[]>("/v1/integrations"),
    ]);
    if (cat.status === "fulfilled") setCatalogue(cat.value);
    if (mine.status === "fulfilled") setConnected(mine.value);
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  // The browser is already here, so there is no link token to mint and no new
  // tab to open — the connect page is just another route on this origin.
  async function connect(connectorId: string) {
    setBusy(connectorId);
    setProblem(null);
    try {
      const { url } = await api<{ url: string }>(`/v1/connect/${connectorId}`, { method: "POST" });
      window.location.href = url;
    } catch (error) {
      setProblem(error instanceof ApiError ? error.message : "We could not start that connection.");
      setBusy(null);
    }
  }

  async function disconnect(row: Integration) {
    setBusy(row.id);
    setProblem(null);
    try {
      await api(`/v1/integrations/${row.id}`, { method: "DELETE" });
      await refresh();
    } catch (error) {
      setProblem(error instanceof ApiError ? error.message : "We could not disconnect that.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Integrations</h1>
        <p className="mt-1 text-sm text-white/55">
          Connect an account here and its metrics become available to every widget.
        </p>
      </div>

      {problem && (
        <p className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-300">
          {problem}
        </p>
      )}

      {connected.length > 0 && (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-medium text-white/50">Connected</h2>
          {connected.map((row) => (
            <ConnectedRow
              key={row.id}
              row={row}
              accent={accentFor(catalogue, row.provider)}
              busy={busy === row.id}
              onDisconnect={() => void disconnect(row)}
            />
          ))}
        </section>
      )}

      {catalogue === null ? (
        <p className="text-sm text-white/40">Loading the catalogue…</p>
      ) : (
        catalogue.categories.map((group) => (
          <section key={group.id} className="flex flex-col gap-2">
            <h2 className="text-sm font-medium text-white/50">{group.label}</h2>
            {group.connectors.map((connector) => (
              <AvailableRow
                key={connector.id}
                connector={connector}
                count={connected.filter((row) => row.provider === connector.id).length}
                busy={busy === connector.id}
                onConnect={() => void connect(connector.id)}
              />
            ))}
          </section>
        ))
      )}
    </div>
  );
}

function accentFor(catalogue: Catalogue | null, provider: string): string {
  for (const group of catalogue?.categories ?? []) {
    const hit = group.connectors.find((connector) => connector.id === provider);
    if (hit) return hit.accentColor;
  }
  return "#6b7280";
}

function ConnectedRow({
  row,
  accent,
  busy,
  onDisconnect,
}: {
  row: Integration;
  accent: string;
  busy: boolean;
  onDisconnect: () => void;
}) {
  const broken = row.status === "auth_failed";
  return (
    <div className="flex items-center gap-3.5 rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3">
      <ConnectorMark id={row.provider} name={row.label} accentColor={accent} />
      <div className="min-w-0 flex-1">
        <p className="truncate font-medium">{row.accountLabel ?? row.label}</p>
        <p className="truncate text-sm text-white/45">
          {broken ? (
            <span className="text-amber-300">Stopped working — reconnect to start it again</span>
          ) : (
            <>
              {row.credentialHint}
              {row.lastSyncedAt
                ? ` · synced ${new Date(row.lastSyncedAt).toLocaleString()}`
                : " · not synced yet"}
            </>
          )}
        </p>
      </div>
      <button
        type="button"
        onClick={onDisconnect}
        disabled={busy}
        className="border-white/12 shrink-0 rounded-lg border px-3 py-1.5 text-sm text-white/70 transition hover:border-red-500/40 hover:text-red-300 disabled:opacity-50"
      >
        {busy ? "Removing…" : "Disconnect"}
      </button>
    </div>
  );
}

function AvailableRow({
  connector,
  count,
  busy,
  onConnect,
}: {
  connector: ConnectorEntry;
  count: number;
  busy: boolean;
  onConnect: () => void;
}) {
  const ready = connector.status !== "coming_soon";
  return (
    <div className="border-white/8 flex items-center gap-3.5 rounded-xl border px-4 py-3">
      <ConnectorMark id={connector.id} name={connector.name} accentColor={connector.accentColor} />
      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-2 font-medium">
          {connector.name}
          {connector.authMode === "oauth2" && (
            <span className="rounded border border-white/15 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-white/45">
              OAuth
            </span>
          )}
        </p>
        <p className="truncate text-sm text-white/45">{connector.tagline}</p>
      </div>
      {ready ? (
        <button
          type="button"
          onClick={onConnect}
          disabled={busy}
          className="shrink-0 rounded-lg bg-blue-600 px-3.5 py-1.5 text-sm font-semibold transition hover:bg-blue-500 disabled:opacity-50"
        >
          {busy ? "Opening…" : count > 0 ? "Add another" : "Connect"}
        </button>
      ) : (
        <span className="shrink-0 text-sm text-white/30">Soon</span>
      )}
    </div>
  );
}
