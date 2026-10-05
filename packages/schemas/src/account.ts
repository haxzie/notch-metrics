import { z } from "zod";
import { CurrencyCode } from "./money.ts";
import { BillingState } from "./billing.ts";

export const User = z.object({
  id: z.string(),
  name: z.string().nullable(),
  email: z.string(),
  image: z.string().nullable(),
  /** IANA zone. Day buckets are the user's day, not UTC's. */
  timezone: z.string(),
  /**
   * The one currency metrics are reported in.
   *
   * Transactions in other currencies are excluded with a visible note rather
   * than converted. Summing mixed currencies at 1:1 is the kind of wrong that
   * looks right, and an FX rate is a product decision, not a default.
   */
  preferredCurrency: CurrencyCode,
  createdAt: z.string(),
});
export type User = z.infer<typeof User>;

export const MeResponse = z.object({
  user: User,
  billing: BillingState,
  counts: z.object({ integrations: z.number().int(), widgets: z.number().int() }),
});
export type MeResponse = z.infer<typeof MeResponse>;

export const Device = z.object({
  id: z.string(),
  label: z.string(),
  lastUsedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type Device = z.infer<typeof Device>;

export const DesktopAuthorizeRequest = z.object({
  /** base64url(SHA-256(verifier)). The verifier never leaves the Mac. */
  challenge: z.string().min(32).max(128),
});
export type DesktopAuthorizeRequest = z.infer<typeof DesktopAuthorizeRequest>;

export const DesktopTokenRequest = z.object({
  code: z.string().min(16).max(128),
  verifier: z.string().min(32).max(128),
  label: z.string().min(1).max(80),
});
export type DesktopTokenRequest = z.infer<typeof DesktopTokenRequest>;

export const DesktopTokenResponse = z.object({
  token: z.string(),
  user: User,
  billing: BillingState,
});
export type DesktopTokenResponse = z.infer<typeof DesktopTokenResponse>;
