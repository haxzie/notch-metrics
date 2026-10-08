"use client";

import { useEffect, useState } from "react";

/**
 * The desktop sign-in handshake.
 *
 * The Mac app opens this with a PKCE challenge, we exchange it for a one-time
 * code against the API, and then navigate to the app's own URL scheme.
 */
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com";

// A compile-time constant, deliberately not a query parameter. If the app
// could pass its own redirect target, anything that could open this page could
// have a code minted for the signed-in user delivered to a scheme it chose.
const CALLBACK = "notchmetrics://auth/callback";

type Status = "working" | "needsSignIn" | "handed-off" | "failed";

/** The login page, told to come back here with the challenge intact. */
function loginUrl(): string {
  const here =
    typeof window === "undefined"
      ? "/desktop/auth"
      : window.location.pathname + window.location.search;
  return `/login?next=${encodeURIComponent(here)}`;
}

export default function DesktopAuth() {
  const [status, setStatus] = useState<Status>("working");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const challenge = params.get("challenge");
    const state = params.get("state");

    if (!challenge || !state) {
      setStatus("failed");
      setMessage("This link is missing information. Start again from the app.");
      return;
    }

    void (async () => {
      try {
        const response = await fetch(`${API_URL}/v1/desktop/authorize`, {
          method: "POST",
          credentials: "include",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ challenge }),
        });

        if (response.status === 401) {
          // Straight to the login page, with this URL as the way back. The
          // page used to stop here and show a "Sign in" button, which read
          // as the sign-in page having failed to load rather than as a step
          // on the way to it. The button below stays as the fallback for a
          // browser that blocks the navigation.
          setStatus("needsSignIn");
          window.location.replace(loginUrl());
          return;
        }
        if (!response.ok) throw new Error(String(response.status));

        const { code } = (await response.json()) as { code: string };

        // `state` is echoed back untouched; the app compares it with what it
        // generated, which is the CSRF guard on its side.
        window.location.href = `${CALLBACK}?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`;
        setStatus("handed-off");
      } catch {
        setStatus("failed");
        setMessage("We could not complete the sign-in. Try again from the app.");
      }
    })();
  }, []);

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6 text-center">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/logo.svg" alt="" width={36} height={36} />

      {status === "working" && <p className="text-white/60">Connecting your Mac…</p>}

      {status === "needsSignIn" && (
        <>
          <h1 className="text-xl font-semibold">Taking you to sign in…</h1>
          <p className="text-sm text-white/60">
            Sign in and this page will finish connecting the app.
          </p>
          <a
            href={loginUrl()}
            className="brand-gradient rounded-full px-5 py-2.5 text-sm font-semibold text-black"
          >
            Continue
          </a>
        </>
      )}

      {status === "handed-off" && (
        <>
          <h1 className="text-xl font-semibold">All set</h1>
          <p className="text-sm text-white/60">
            Notch Metrics is signed in. You can close this tab.
          </p>
        </>
      )}

      {status === "failed" && (
        <>
          <h1 className="text-xl font-semibold">Something went wrong</h1>
          <p className="text-sm text-white/60">{message}</p>
        </>
      )}
    </main>
  );
}
