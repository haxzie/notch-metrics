import { z } from "zod";

/**
 * Money is always an integer in minor units plus an ISO 4217 code.
 *
 * Never a float. A dashboard that stores money as a double is a dashboard that
 * eventually renders `$1,234.5600000001`, and the bug is unreproducible because
 * it depends on which additions happened in which order.
 */
export const CurrencyCode = z
  .string()
  .length(3)
  .regex(/^[A-Z]{3}$/);
export type CurrencyCode = z.infer<typeof CurrencyCode>;

export const Money = z.object({
  /** Minor units. 1234 is $12.34 in USD, and ¥1234 in JPY (which has no minor unit). */
  amount: z.number().int(),
  currency: CurrencyCode,
});
export type Money = z.infer<typeof Money>;

export const Granularity = z.enum(["hour", "day", "week", "month"]);
export type Granularity = z.infer<typeof Granularity>;

/**
 * A relative window the client asks for. `from`/`to` on the request override it.
 * Kept as a closed enum so the cache key stays small and enumerable.
 */
export const TimeRange = z.enum(["24h", "7d", "30d", "90d", "12m"]);
export type TimeRange = z.infer<typeof TimeRange>;

export const RANGE_DURATION_MS: Record<TimeRange, number> = {
  "24h": 24 * 60 * 60 * 1000,
  "7d": 7 * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000,
  "90d": 90 * 24 * 60 * 60 * 1000,
  "12m": 365 * 24 * 60 * 60 * 1000,
};

export const DEFAULT_GRANULARITY: Record<TimeRange, Granularity> = {
  "24h": "hour",
  "7d": "day",
  "30d": "day",
  "90d": "week",
  "12m": "month",
};
