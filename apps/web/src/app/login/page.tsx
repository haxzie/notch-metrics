"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { signIn, useSession } from "@/lib/auth-client";

function LoginForm() {
  const params = useSearchParams();
  const { data: session, isPending } = useSession();
  // Only ever a path on this origin. A full URL here would turn the login
  // page into an open redirect that arrives already signed in.
  const raw = params.get("next") ?? "/app";
  const next = raw.startsWith("/") && !raw.startsWith("//") ? raw : "/app";

  /**
   * Absolute, and deliberately so.
   *
   * Better Auth resolves a relative `callbackURL` against *its own* base URL,
   * which is the API — so handing it "/desktop/auth?challenge=…" sent people
   * to api…/desktop/auth, a route only the website has, and the Worker
   * answered with its own "No such endpoint" JSON. The path is still
   * validated as same-origin above; this only names the origin.
   */
  const callbackURL =
    typeof window === "undefined" ? next : new URL(next, window.location.origin).toString();

  if (!isPending && session) {
    if (typeof window !== "undefined") window.location.replace(next);
    return <p className="text-white/60">Taking you back…</p>;
  }

  return (
    <>
      <h1 className="text-2xl font-semibold">Sign in to Notch Metrics</h1>
      <p className="text-sm text-white/60">
        Your metrics, your integrations and your billing all live behind one account.
      </p>
      <button
        type="button"
        onClick={() => void signIn.social({ provider: "google", callbackURL })}
        className="mt-4 flex w-full items-center justify-center gap-2.5 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-white/90"
      >
        <GoogleMark />
        Continue with Google
      </button>
      <button
        type="button"
        onClick={() => void signIn.social({ provider: "github", callbackURL })}
        className="flex w-full items-center justify-center gap-2.5 rounded-xl bg-white/10 px-4 py-2.5 text-sm font-semibold text-white ring-1 ring-white/15 transition hover:bg-white/15"
      >
        <GitHubMark />
        Continue with GitHub
      </button>
      <p className="text-xs text-white/40">
        By continuing you agree to the{" "}
        <a href="/terms" className="underline">
          terms
        </a>{" "}
        and{" "}
        <a href="/privacy" className="underline">
          privacy policy
        </a>
        .
      </p>
    </>
  );
}

export default function Login() {
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col items-center justify-center gap-3 px-6 text-center">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/logo.svg" alt="" width={40} height={40} />
      <Suspense fallback={<p className="text-white/60">Loading…</p>}>
        <LoginForm />
      </Suspense>
    </main>
  );
}

function GitHubMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
      <path
        fill="currentColor"
        d="M12 .3a12 12 0 0 0-3.79 23.4c.6.1.82-.26.82-.58v-2.23c-3.34.73-4.04-1.42-4.04-1.42-.55-1.38-1.33-1.75-1.33-1.75-1.09-.74.08-.73.08-.73 1.2.09 1.84 1.24 1.84 1.24 1.07 1.83 2.8 1.3 3.49 1 .1-.78.42-1.3.76-1.6-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.14-.3-.54-1.52.1-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6.01 0c2.29-1.55 3.3-1.23 3.3-1.23.64 1.66.24 2.88.12 3.18a4.65 4.65 0 0 1 1.23 3.22c0 4.61-2.8 5.63-5.48 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.21.7.82.58A12 12 0 0 0 12 .3"
      />
    </svg>
  );
}

function GoogleMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1Z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.65l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23Z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.11a6.6 6.6 0 0 1 0-4.22V7.05H2.18a11 11 0 0 0 0 9.9l3.66-2.84Z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1a11 11 0 0 0-9.82 6.05l3.66 2.84c.87-2.6 3.3-4.51 6.16-4.51Z"
      />
    </svg>
  );
}
