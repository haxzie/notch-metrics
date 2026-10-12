import { z } from "zod";
import { CurrencyCode, Granularity, TimeRange } from "./money.ts";
import { IntegrationId, MetricId } from "./ids.ts";
import { NotificationCursor } from "./notification.ts";

export const MetricUnit = z.enum(["currency", "count", "ratio", "duration", "bytes"]);
export type MetricUnit = z.infer<typeof MetricUnit>;

export const MetricPoint = z.object({
  /** ISO-8601 instant at the *start* of the bucket. */
  t: z.string(),
  /** Minor units when the unit is `currency`; a plain number otherwise. */
  v: z.number(),
});
export type MetricPoint = z.infer<typeof MetricPoint>;

export const MetricFormat = z.object({
  decimals: z.number().int().min(0).max(4).default(0),
  /** 12_300 renders as "12.3k". */
  compact: z.boolean().default(true),
  prefix: z.string().max(3).default(""),
  suffix: z.string().max(4).default(""),
});
export type MetricFormat = z.infer<typeof MetricFormat>;

/**
 * One row of a list widget — a payment, an order, a signup.
 *
 * A list is still a `MetricSeries`: it has a headline value and sits in the
 * same cache, the same batch and the same error envelope as a number. What
 * it adds is `items`, which the tile renders as rows instead of a figure.
 */
export const MetricListItem = z.object({
  id: z.string(),
  /** ISO-8601 instant the row happened at. */
  t: z.string(),
  /** Who or what: a customer name, an email, a product. */
  label: z.string(),
  /** A second line, when there is one — the product under the customer. */
  detail: z.string().nullable(),
  /** Minor units of `currency`. Null for a row without an amount. */
  amount: z.number().nullable(),
  currency: CurrencyCode.nullable(),
  /** The provider's own word for the row's state, e.g. `refunded`. */
  status: z.string().nullable(),
});
export type MetricListItem = z.infer<typeof MetricListItem>;

export const MetricDelta = z.object({
  /** Same units as `value`. */
  absolute: z.number(),
  /** Null when the previous window was zero — 0 → 5 has no percentage. */
  percent: z.number().nullable(),
});
export type MetricDelta = z.infer<typeof MetricDelta>;

/**
 * The normalised shape every provider and every plugin collapses to, and the
 * only metric shape the Mac app decodes.
 *
 * `value` is deliberately not always `sum(points)`. MRR is a snapshot of the
 * subscription book at `to`; revenue is a total over the window. Collapsing
 * both into "the sum of the series" would quietly make MRR wrong.
 */
export const MetricSeries = z.object({
  integrationId: IntegrationId.nullable(),
  metric: z.string(),
  unit: MetricUnit,
  currency: CurrencyCode.nullable(),
  value: z.number(),
  previousValue: z.number().nullable(),
  delta: MetricDelta.nullable(),
  points: z.array(MetricPoint),
  granularity: Granularity,
  range: TimeRange,
  from: z.string(),
  to: z.string(),
  format: MetricFormat.nullable(),
  /** When the data was computed, not when it was served. */
  generatedAt: z.string(),
  /** True when served past its TTL because a refresh failed or is in flight. */
  stale: z.boolean().default(false),
  /**
   * Rows, for a list metric. Absent for a number.
   *
   * Optional rather than defaulted to `[]`, so an older app ignores the
   * field and a newer one can tell "a list with nothing in it" from "not a
   * list".
   */
  items: z.array(MetricListItem).optional(),
});
export type MetricSeries = z.infer<typeof MetricSeries>;

export const MetricErrorCode = z.enum([
  "auth_failed",
  "rate_limited",
  "provider_down",
  "unsupported",
  "not_found",
  "stale",
]);
export type MetricErrorCode = z.infer<typeof MetricErrorCode>;

/**
 * Carried inside a 200, never as an HTTP status.
 *
 * `POST /v1/metrics/batch` returns one result per request and partial success is
 * the normal case: a status code cannot be per-item, and one broken provider
 * must not blank a notch that has four working widgets in it.
 */
export const MetricError = z.object({
  ok: z.literal(false),
  integrationId: IntegrationId.nullable(),
  metric: z.string(),
  code: MetricErrorCode,
  message: z.string(),
  retryAfterSeconds: z.number().int().nullable().default(null),
});
export type MetricError = z.infer<typeof MetricError>;

export const MetricEnvelope = z.object({
  ok: z.literal(true),
  series: MetricSeries,
});
export type MetricEnvelope = z.infer<typeof MetricEnvelope>;

export const MetricResult = z.union([MetricEnvelope, MetricError]);
export type MetricResult = z.infer<typeof MetricResult>;

/**
 * Per-widget arguments to a metric — a GitHub repository, say.
 *
 * Bounded on every axis because this is user input that ends up in a cache
 * key and in a provider request path. Opaque to everything in between: the
 * adapter that declared the keys is the only thing that reads them.
 */
export const MetricParams = z
  .record(z.string().regex(/^[a-z][a-z0-9_]{0,31}$/), z.string().max(200))
  .refine((p) => Object.keys(p).length <= 8, "Too many parameters.")
  .default({});
export type MetricParams = z.infer<typeof MetricParams>;

export const MetricQuery = z.object({
  integrationId: IntegrationId,
  metric: MetricId,
  granularity: Granularity.optional(),
  range: TimeRange.default("30d"),
  /** Suppress the series when the widget only renders a number. */
  series: z.boolean().default(true),
  /** See `MetricParams`. Part of the cache key — see `cacheKey` in the API. */
  params: MetricParams,
});
export type MetricQuery = z.infer<typeof MetricQuery>;

export const MetricBatchRequest = z.object({
  /**
   * Capped at twelve because the notch holds at most sixteen 1x1 tiles and a
   * single Worker invocation has a wall-clock budget. An uncapped batch is a
   * way to turn one request into fifty outbound provider calls.
   */
  requests: z.array(MetricQuery).min(1).max(12),
});
export type MetricBatchRequest = z.infer<typeof MetricBatchRequest>;

export const MetricBatchResponse = z.object({
  /** Index-aligned with the request array. */
  results: z.array(MetricResult),
  /**
   * Notification state, riding along.
   *
   * The Mac already makes this request on a timer for the whole layout, so
   * carrying the unread count here costs zero extra requests and keeps working
   * in every power state — including Low Power Mode, where the cheap cursor
   * poll is switched off entirely. It is the backstop under that poll, not a
   * replacement for it.
   *
   * Optional rather than defaulted so the committed `metric-batch` fixture and
   * every already-shipped Swift decoder are untouched by this field arriving.
   */
  notifications: NotificationCursor.optional(),
});
export type MetricBatchResponse = z.infer<typeof MetricBatchResponse>;

export const MetricCatalogEntry = z.object({
  integrationId: IntegrationId,
  provider: z.string(),
  accountLabel: z.string().nullable(),
  metric: MetricId,
  label: z.string(),
  shortLabel: z.string(),
  unit: MetricUnit,
  currency: CurrencyCode.nullable(),
  granularities: z.array(Granularity),
  supportsSeries: z.boolean(),
});
export type MetricCatalogEntry = z.infer<typeof MetricCatalogEntry>;
