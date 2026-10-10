import type { MetricFormat } from "@notch/schemas";
import type { ZodType } from "zod";
import type { CurrencyCode, Granularity, MetricId, ProviderManifest } from "@notch/schemas";
import type { OAuthConfig } from "./oauth.ts";

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
  /**
   * What this particular widget is asking about — the keys the metric's
   * `params` declared in the manifest, e.g. `{ repository: "owner/name" }`.
   *
   * Validated against the declaration before it arrives, but still user
   * input: an adapter putting one of these in a URL path must encode it.
   */
  params: Record<string, string>;
}

/** A row of a list metric. See `MetricListItem` in `@notch/schemas`. */
export interface RawListItem {
  id: string;
  t: Date;
  label: string;
  detail: string | null;
  /** Minor units of `currency`; null for a row with no amount. */
  amount: number | null;
  currency: string | null;
  status: string | null;
}

export interface RawSeries {
  /**
   * A subset of `MetricUnit`: no `bytes`, because nothing fetched over HTTP
   * from a SaaS API is a size. `duration` is seconds — the Mac formatter
   * divides by 60 and 3600 — so a provider reporting minutes converts here
   * rather than leaving the tile to read "45s" for forty-five minutes.
   */
  unit: "currency" | "count" | "ratio" | "duration";
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
  /** Rows, for a list metric such as `recent_payments`. Absent for a number. */
  items?: RawListItem[];
  /**
   * How the tile should render the figure, when the unit alone gets it
   * wrong. Search Console's average position is a `count` of 12.3, not 12;
   * without this it rounds to a whole number or, as a `ratio`, reads 1230%.
   */
  format?: Partial<MetricFormat>;
}

export type ProviderErrorCode =
  "auth_failed" | "rate_limited" | "provider_down" | "unsupported" | "bad_response";

export class ProviderError extends Error {
  // Declared and assigned rather than written as constructor parameter
  // properties. Those are one of the few TypeScript features that cannot be
  // erased by type-stripping alone, so they make the whole package
  // unloadable under `node --experimental-strip-types` — which the contract
  // emitter and any plain-Node script rely on.
  readonly code: ProviderErrorCode;
  readonly retryAfterSeconds?: number;

  constructor(code: ProviderErrorCode, message: string, retryAfterSeconds?: number) {
    super(message);
    this.name = "ProviderError";
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
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

/**
 * A connector: one external account the notch can read numbers from.
 *
 * Adding one is a directory under `providers/`, a line in the registry, and a
 * test. Nothing else changes — the catalogue, the connect flow, the settings
 * UI and the OAuth callback all read the registry generically, which is the
 * property that lets a provider ship without a Mac release.
 */
export interface ProviderAdapter<C extends Record<string, unknown> = Record<string, unknown>> {
  readonly manifest: ProviderManifest;
  /** The one schema for the credentials the connect page produces. */
  readonly credentialSchema: ZodType<C>;

  /**
   * Which credential fields a human types.
   *
   * OAuth connectors store tokens in the same blob, and those must never be
   * rendered as a form field or accepted from a submission. Omitted means
   * "every field in the schema", which is right for a bare API key and wrong
   * for anything with tokens in it.
   */
  readonly userInputFields?: readonly string[];

  /** Present only for `authMode: "oauth2"`. */
  readonly oauth?: OAuthConfig<C>;

  /** Proves the credentials work. Called before any row is written. */
  verify(ctx: AdapterContext, credentials: C): Promise<VerifyResult>;

  fetchMetric(ctx: AdapterContext, credentials: C, request: MetricRequest): Promise<RawSeries>;
}

/** Thrown by a connector that is declared but not implemented yet. */
export function notImplemented(name: string): never {
  throw new ProviderError("unsupported", `The ${name} integration is not ready yet.`);
}
