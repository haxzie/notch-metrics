import type { Granularity } from "@notch/schemas";

/** Start of the bucket `date` falls in, in the given IANA zone. */
export function bucketStart(date: Date, granularity: Granularity, timeZone: string): Date {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(date);

  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  const [y, m, d, h] = [get("year"), get("month"), get("day"), get("hour") % 24];

  switch (granularity) {
    case "hour":
      return new Date(Date.UTC(y, m - 1, d, h));
    case "day":
      return new Date(Date.UTC(y, m - 1, d));
    case "week": {
      const utc = new Date(Date.UTC(y, m - 1, d));
      // ISO weeks start on Monday. getUTCDay() is 0 for Sunday.
      const offset = (utc.getUTCDay() + 6) % 7;
      utc.setUTCDate(utc.getUTCDate() - offset);
      return utc;
    }
    case "month":
      return new Date(Date.UTC(y, m - 1, 1));
  }
}

function advance(date: Date, granularity: Granularity): Date {
  const next = new Date(date);
  switch (granularity) {
    case "hour":
      next.setUTCHours(next.getUTCHours() + 1);
      break;
    case "day":
      next.setUTCDate(next.getUTCDate() + 1);
      break;
    case "week":
      next.setUTCDate(next.getUTCDate() + 7);
      break;
    case "month":
      next.setUTCMonth(next.getUTCMonth() + 1);
      break;
  }
  return next;
}

/**
 * Sums `events` into contiguous buckets, including the empty ones.
 *
 * Gap-filling is not cosmetic: a sparkline drawn from only the non-zero days
 * compresses a quiet week into a single step and makes a flat month look like
 * growth.
 */
export function bucketSum(
  events: { at: Date; amount: number }[],
  options: { from: Date; to: Date; granularity: Granularity; timeZone: string },
): { t: Date; v: number }[] {
  const { from, to, granularity, timeZone } = options;
  const totals = new Map<number, number>();

  for (const event of events) {
    const key = bucketStart(event.at, granularity, timeZone).getTime();
    totals.set(key, (totals.get(key) ?? 0) + event.amount);
  }

  const points: { t: Date; v: number }[] = [];
  let cursor = bucketStart(from, granularity, timeZone);
  const end = bucketStart(to, granularity, timeZone);
  // A guard rather than a `while (cursor <= end)` alone: a bad granularity or a
  // reversed range would otherwise allocate until the Worker is killed.
  for (let i = 0; cursor <= end && i < 1000; i++) {
    points.push({ t: new Date(cursor), v: totals.get(cursor.getTime()) ?? 0 });
    cursor = advance(cursor, granularity);
  }
  return points;
}

/** Null when `previous` is zero — 0 → 5 has no meaningful percentage. */
export function percentChange(current: number, previous: number | null): number | null {
  if (previous === null || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 10_000) / 100;
}

/**
 * A recurring amount expressed per month.
 *
 * Years divide by twelve; weeks and days are scaled by the average month, which
 * is the only honest answer — "monthly" recurring revenue from a weekly plan is
 * a convention, not a fact, and `methodology` on the metric descriptor says so.
 */
export function toMonthly(amount: number, interval: string, intervalCount = 1): number {
  const perInterval = amount / Math.max(1, intervalCount);
  switch (interval) {
    case "month":
      return perInterval;
    case "year":
      return perInterval / 12;
    case "week":
      return (perInterval * 52) / 12;
    case "day":
      return (perInterval * 365) / 12;
    default:
      return perInterval;
  }
}

/**
 * `YYYY-MM-DD` of a moment in the user's zone.
 *
 * What every date-ranged provider API takes, which is why it lives here
 * rather than beside one provider's OAuth code.
 */
export function ymd(date: Date, timeZone: string): string {
  // en-CA is the locale whose default date format is ISO.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

/** Noon UTC of a `YYYYMMDD` or `YYYY-MM-DD` day, so bucketing lands on that calendar day in any zone within ±11h. */
export function dayAt(ymdValue: string): Date {
  const digits = ymdValue.replace(/-/g, "");
  const y = Number(digits.slice(0, 4));
  const m = Number(digits.slice(4, 6));
  const d = Number(digits.slice(6, 8));
  return new Date(Date.UTC(y, m - 1, d, 12));
}

/**
 * ISO 4217 minor-unit exponents that are not 2.
 *
 * Only the exceptions are listed; everything absent has two decimal places.
 * A provider reporting "1234.00 JPY" means ¥1234, and multiplying it by a
 * hundred because every other currency works that way overstates a Japanese
 * store's revenue by a factor of a hundred.
 */
const MINOR_UNIT_EXPONENT: Record<string, number> = {
  BIF: 0,
  CLP: 0,
  DJF: 0,
  GNF: 0,
  ISK: 0,
  JPY: 0,
  KMF: 0,
  KRW: 0,
  PYG: 0,
  RWF: 0,
  UGX: 0,
  UYI: 0,
  VND: 0,
  VUV: 0,
  XAF: 0,
  XOF: 0,
  XPF: 0,
  BHD: 3,
  IQD: 3,
  JOD: 3,
  KWD: 3,
  LYD: 3,
  OMR: 3,
  TND: 3,
};

/**
 * A provider's decimal major-unit amount as integer minor units.
 *
 * $12.34 is 1234 and ¥1234 is 1234 — the exponent depends on the currency,
 * not on how many digits the provider happened to print. Rounded rather than
 * truncated, so a half-cent from a tax or discount split does not vanish.
 */
export function toMinorUnits(amount: number, currency: string): number {
  const exponent = MINOR_UNIT_EXPONENT[currency.toUpperCase()] ?? 2;
  return Math.round(amount * 10 ** exponent);
}
