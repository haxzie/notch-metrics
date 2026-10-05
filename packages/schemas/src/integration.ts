import { z } from "zod";
import { CurrencyCode } from "./money.ts";
import { IntegrationId, MetricId, ProviderId } from "./ids.ts";

export const IntegrationStatus = z.enum(["ok", "auth_failed", "rate_limited", "disabled"]);
export type IntegrationStatus = z.infer<typeof IntegrationStatus>;

/**
 * The *public* shape of an integration. Everything the API will ever return.
 *
 * There is no field here for the credential, encrypted or otherwise. That is
 * the point: the ciphertext never leaves the Worker, so a bug in a route
 * handler cannot leak it. `credentialHint` is first-eight plus last-four,
 * which is enough for a human to tell two Stripe keys apart and not enough to
 * be one.
 */
export const Integration = z.object({
  id: IntegrationId,
  provider: ProviderId,
  label: z.string(),
  status: IntegrationStatus,
  credentialHint: z.string(),
  accountLabel: z.string().nullable(),
  accountCurrency: CurrencyCode.nullable(),
  enabledMetrics: z.array(MetricId),
  availableMetrics: z.array(MetricId),
  lastSyncedAt: z.string().nullable(),
  lastErrorAt: z.string().nullable(),
  lastErrorCode: z.string().nullable(),
  createdAt: z.string(),
});
export type Integration = z.infer<typeof Integration>;

export const IntegrationCreate = z.object({
  provider: ProviderId,
  label: z.string().min(1).max(60).optional(),
  /** Validated against the adapter's own `credentialSchema` before use. */
  credentials: z.record(z.string(), z.string()),
});
export type IntegrationCreate = z.infer<typeof IntegrationCreate>;

export const IntegrationUpdate = z.object({
  label: z.string().min(1).max(60).optional(),
  credentials: z.record(z.string(), z.string()).optional(),
  enabledMetrics: z.array(MetricId).optional(),
  disabled: z.boolean().optional(),
});
export type IntegrationUpdate = z.infer<typeof IntegrationUpdate>;

export const VerifyResponse = z.object({
  ok: z.boolean(),
  accountLabel: z.string().nullable(),
  currency: CurrencyCode.nullable(),
  availableMetrics: z.array(MetricId),
  code: z.string().nullable().default(null),
  message: z.string().nullable().default(null),
});
export type VerifyResponse = z.infer<typeof VerifyResponse>;
