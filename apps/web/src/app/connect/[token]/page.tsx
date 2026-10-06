"use client";

import { use, useEffect, useState } from "react";
import { ConnectorMark } from "@/components/ConnectorMark";

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
      <Shell connector={connector}>
        <h1 className="text-xl font-semibold">{connector.name} is connected</h1>
        <p className="text-sm text-white/60">
          {load.label ? `Connected as ${load.label}. ` : ""}You can close this tab and go back to
          the app.
        </p>
      </Shell>
    );
  }

  return (
    <Shell connector={connector}>
      <h1 className="text-xl font-semibold">Connect {connector.name}</h1>
      <p className="text-sm text-white/60">{connector.tagline}</p>

      <form onSubmit={submit} className="mt-4 flex w-full flex-col gap-4 text-left">
        {connector.fields.map((field) => (
          <label key={field.key} className="flex flex-col gap-1.5">
            <span className="text-sm font-medium">{field.label}</span>

            {field.type === "select" ? (
              // `appearance-none` plus our own chevron: the platform arrow is
              // drawn hard against the right edge and no amount of padding
              // moves it.
              <div className="relative">
                <select
                  className="w-full appearance-none rounded-lg border border-white/10 bg-white/5 py-2 pl-3 pr-10 text-sm"
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
                <svg
                  viewBox="0 0 16 16"
                  aria-hidden
                  className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-white/45"
                >
                  <path
                    d="M4 6.5 8 10.5 12 6.5"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </div>
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
          // White rather than the brand colour: half of these brands are dark
          // enough that the primary action read as a disabled grey block.
          className="rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-white/90 disabled:opacity-50"
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

function Shell({
  children,
  connector,
}: {
  children: React.ReactNode;
  connector?: { id: string; name: string; accentColor: string };
}) {
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
      {connector ? (
        <ConnectPair connector={connector} />
      ) : (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img src="/logo.svg" alt="" width={36} height={36} />
      )}
      {children}
    </main>
  );
}

/**
 * The two apps being joined, as overlapping tiles.
 *
 * Says what the page is for before any of the words are read: this is *your*
 * Notch Metrics talking to *that* service, rather than a bare credentials
 * form that could have come from anywhere — which is the moment somebody
 * decides whether to paste an API key.
 */
function ConnectPair({
  connector,
}: {
  connector: { id: string; name: string; accentColor: string };
}) {
  return (
    <div className="mb-3 flex items-center justify-center">
      <span
        className="flex size-16 rotate-[-8deg] items-center justify-center rounded-[28%] bg-[#15101f] shadow-lg shadow-black/40 ring-1 ring-white/10"
        aria-hidden
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.svg" alt="" width={32} height={32} />
      </span>
      {/* Pulled left so the tiles overlap, and above in the stacking order so
          the connector reads as the thing being added. */}
      <span className="z-10 -ml-4 rotate-[8deg] rounded-[28%] shadow-lg shadow-black/40">
        <ConnectorMark
          id={connector.id}
          name={connector.name}
          accentColor={connector.accentColor}
          size={64}
        />
      </span>
    </div>
  );
}
