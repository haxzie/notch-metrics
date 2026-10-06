"use client";

import { use, useEffect, useState } from "react";

/**
 * The other end of the desktop app's Connect button.
 *
 * The app mints a short-lived link token and opens this page in the browser.
 * The token *is* the authorisation here — this page never has the app's device
 * token and never asks the user to sign in again, which is the whole point of
 * the flow.
 */
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com";

type Field = {
  key: string;
  label: string;
  help?: string;
  type: "string" | "secret" | "select" | "url";
  required: boolean;
  placeholder?: string;
  options?: { value: string; label: string }[];
};

type Connector = {
  id: string;
  name: string;
  tagline: string;
  docsUrl?: string;
  accentColor: string;
  authMode: "api_key" | "oauth2";
  oauth: { scopeSummary: string } | null;
  fields: Field[];
};

type Load =
  | { phase: "loading" }
  | { phase: "ready"; connector: Connector }
  | { phase: "done"; connector: Connector; label?: string }
  | { phase: "dead"; message: string };

export default function ConnectPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [load, setLoad] = useState<Load>({ phase: "loading" });
  const [values, setValues] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        const response = await fetch(`${API_URL}/v1/link/${encodeURIComponent(token)}`);
        const body = await response.json();
        if (!response.ok) {
          setLoad({ phase: "dead", message: body.message ?? "This link is no longer valid." });
          return;
        }
        setLoad({ phase: "ready", connector: body.connector });
        // Pre-seed selects so a user who accepts every default can just submit.
        setValues(
          Object.fromEntries(
            (body.connector.fields as Field[])
              .filter((f) => f.type === "select" && f.options?.[0])
              .map((f) => [f.key, f.options![0]!.value]),
          ),
        );
      } catch {
        setLoad({ phase: "dead", message: "We could not reach Notch Metrics. Try again." });
      }
    })();
  }, [token]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (load.phase !== "ready") return;
    setSubmitting(true);
    setProblem(null);
    try {
      const response = await fetch(`${API_URL}/v1/link/${encodeURIComponent(token)}/submit`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(values),
      });
      const body = await response.json();
      if (!response.ok) {
        // The credentials stay in the form. Making someone retype a 64-character
        // key because one field was wrong is how people give up here.
        setProblem(body.message ?? "We could not verify those details.");
        return;
      }
      setLoad({ phase: "done", connector: load.connector, label: body.accountLabel });
      // Hands control back to the app, which is already polling for this.
      window.location.href = body.returnTo;
    } catch {
      setProblem("We could not verify those details.");
    } finally {
      setSubmitting(false);
    }
  }

  if (load.phase === "loading") {
    return (
      <Shell>
        <p className="text-white/60">Loading…</p>
      </Shell>
    );
  }

  if (load.phase === "dead") {
    return (
      <Shell>
        <h1 className="text-xl font-semibold">That link has expired</h1>
        <p className="text-sm text-white/60">{load.message}</p>
        <p className="text-sm text-white/40">
          Open Notch Metrics and press Connect again — links are good for ten minutes.
        </p>
      </Shell>
    );
  }

  const { connector } = load;

  if (load.phase === "done") {
    return (
      <Shell accent={connector.accentColor}>
        <h1 className="text-xl font-semibold">{connector.name} is connected</h1>
        <p className="text-sm text-white/60">
          {load.label ? `Connected as ${load.label}. ` : ""}You can close this tab and go back to
          the app.
        </p>
      </Shell>
    );
  }

  return (
    <Shell accent={connector.accentColor}>
      <h1 className="text-xl font-semibold">Connect {connector.name}</h1>
      <p className="text-sm text-white/60">{connector.tagline}</p>

      <form onSubmit={submit} className="mt-4 flex w-full flex-col gap-4 text-left">
        {connector.fields.map((field) => (
          <label key={field.key} className="flex flex-col gap-1.5">
            <span className="text-sm font-medium">{field.label}</span>

            {field.type === "select" ? (
              <select
                className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm"
                value={values[field.key] ?? ""}
                onChange={(e) => setValues((v) => ({ ...v, [field.key]: e.target.value }))}
                required={field.required}
              >
                {field.options?.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            ) : (
              <input
                // `secret` renders as a password field so a key is not left on
                // screen during a screen share, which is exactly when people
                // are being walked through this.
                type={field.type === "secret" ? "password" : "text"}
                autoComplete="off"
                spellCheck={false}
                className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 font-mono text-sm"
                placeholder={field.placeholder}
                value={values[field.key] ?? ""}
                onChange={(e) => setValues((v) => ({ ...v, [field.key]: e.target.value }))}
                required={field.required}
              />
            )}

            {field.help && <span className="text-xs text-white/40">{field.help}</span>}
          </label>
        ))}

        {problem && (
          <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-300">
            {problem}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="rounded-lg px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
          style={{ backgroundColor: connector.accentColor }}
        >
          {submitting ? "Verifying…" : `Connect ${connector.name}`}
        </button>

        <p className="text-center text-xs text-white/40">
          We check these details against {connector.name} before saving them. Nothing is stored if
          they do not work.{" "}
          {connector.docsUrl && (
            <a href={connector.docsUrl} target="_blank" rel="noreferrer" className="underline">
              Where to find them
            </a>
          )}
        </p>
      </form>
    </Shell>
  );
}

function Shell({ children, accent }: { children: React.ReactNode; accent?: string }) {
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/logo.svg" alt="" width={36} height={36} style={accent ? { opacity: 0.9 } : {}} />
      {children}
    </main>
  );
}
