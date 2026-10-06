"use client";

import { createAuthClient } from "better-auth/react";

/**
 * Better Auth lives on the Worker, not on this origin, so every call has to
 * carry cookies cross-origin. In development both sides are `localhost` —
 * which is one site for cookie purposes, ports being ignored — so a single
 * sign-in covers :3000 and :8787.
 */
export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com",
  basePath: "/api/auth",
  fetchOptions: { credentials: "include" },
});

export const { useSession, signIn, signOut } = authClient;
