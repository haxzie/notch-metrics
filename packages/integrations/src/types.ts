import type { ZodType } from "zod";
import type { CurrencyCode, Granularity, MetricId, ProviderManifest } from "@notch/schemas";

export interface HttpResponse {
  ok: boolean;
  status: number;
  headers: Headers;
  json<T = unknown>(): Promise<T>;
  text(): Promise<string>;
}

export interface AdapterContext {
  /**
   * The only way an adapter reaches the network.
   *
   * Enforces the manifest's host allowlist, a timeout, a byte cap and
   * `redirect: "manual"`. A bare `fetch` in an adapter is reviewable as a bug:
   * `fetch` re-sends request headers across a same-protocol redirect, so a
   * provider that 302s to an attacker-controlled host would have the user's
   * API key replayed to it by the runtime, with no code of ours involved.
   */
  http(url: string, init?: RequestInit): Promise<HttpResponse>;
  /** Injectable, so bucket boundaries in tests are not wall-clock dependent. */
  now(): Date;
  /** The user's IANA zone. A "day" is theirs, not UTC's. */
  timeZone: string;
  /** The currency metrics are reported in; other currencies are excluded. */
  preferredCurrency: CurrencyCode;
  signal: AbortSignal;
  log(message: string, fields?: Record<string, unknown>): void;
}

export interface MetricRequest {
  metric: MetricId;
  granularity: Granularity;
  from: Date;
  to: Date;
  /** The previous equal-length window, for the delta. Adapters may ignore it. */
  comparePrevious: boolean;
  /** False when the widget renders a number only — lets an adapter skip a walk. */
  wantSeries: boolean;
}

export interface RawSeries {
  unit: "currency" | "count" | "ratio";
  /** Required when unit is `currency`; null when the account mixes currencies. */
  currency: string | null;
  /** Minor units when currency. Integers — see packages/schemas/src/money.ts. */
  points: { t: Date; v: number }[];
  /**
   * The headline figure.
   *
   * Not always `sum(points)`. MRR is a snapshot of the subscription book at
   * `to`; revenue is a total over the window. Deriving one rule for both makes
   * MRR quietly wrong.
   */
  value: number;
  previousValue: number | null;
  /** When the provider itself says it computed this, if it says. */
  asOf?: Date;
  /** Surfaced to the user, e.g. "EUR and GBP charges were excluded." */
  note?: string;
}

export type ProviderErrorCode =
  "auth_failed" | "rate_limited" | "provider_down" | "unsupported" | "bad_response";

export class ProviderError extends Error {
  constructor(
    readonly code: ProviderErrorCode,
    message: string,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

export interface VerifyResult {
  accountLabel: string | null;
  currency: string | null;
  /**
   * May be narrower than the manifest.
   *
   * A Stripe restricted key without the Subscriptions permission can still do
   * revenue. Narrowing here beats failing the whole connection, and the
   * settings UI greys out what is unavailable.
   */
  availableMetrics: MetricId[];
}

export interface ProviderAdapter<C extends Record<string, string> = Record<string, string>> {
  readonly manifest: ProviderManifest;
  /** The one schema for the credentials form's output. */
  readonly credentialSchema: ZodType<C>;
  /** Proves the key works. Called before any row is written. */
  verify(ctx: AdapterContext, credentials: C): Promise<VerifyResult>;
  fetchMetric(ctx: AdapterContext, credentials: C, request: MetricRequest): Promise<RawSeries>;
}
