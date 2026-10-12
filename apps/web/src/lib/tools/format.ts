import type { Unit } from "./types.ts";

/**
 * Number formatting for the calculators.
 *
 * The locale is pinned rather than left to the browser, and that is not a
 * preference. A calculator renders once on the server with its defaults and
 * again on the client when it hydrates; if the two disagree about thousands
 * separators, React throws a hydration mismatch on a page whose only job is
 * to show numbers.
 */
const LOCALE = "en-US";

export const CURRENCIES = ["USD", "GBP", "EUR", "AUD", "CAD", "INR"] as const;
export type Currency = (typeof CURRENCIES)[number];

/** Minor units in, a formatted amount out. Whole amounts lose the `.00`. */
export function formatMoney(minorUnits: number, currency: string): string {
  return new Intl.NumberFormat(LOCALE, {
    style: "currency",
    currency,
    minimumFractionDigits: Number.isInteger(minorUnits / 100) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(minorUnits / 100);
}

export function formatNumber(value: number, decimals = 2): string {
  return new Intl.NumberFormat(LOCALE, {
    maximumFractionDigits: decimals,
  }).format(value);
}

export function formatUnit(value: number | null, unit: Unit, currency: string): string {
  // `null` is a tool saying the inputs cannot produce an answer, usually a
  // zero divisor. Showing a dash is honest; showing 0 or Infinity is not.
  if (value === null || !Number.isFinite(value)) return "—";

  switch (unit) {
    case "money":
      return formatMoney(Math.round(value), currency);
    case "percent":
      return `${formatNumber(value, Math.abs(value) < 10 ? 2 : 1)}%`;
    case "months":
      return `${formatNumber(value, 1)} months`;
    case "count":
      return formatNumber(value, Number.isInteger(value) ? 0 : 2);
  }
}

/** The symbol alone, for an input's prefix. */
export function currencySymbol(currency: string): string {
  const parts = new Intl.NumberFormat(LOCALE, { style: "currency", currency }).formatToParts(0);
  return parts.find((part) => part.type === "currency")?.value ?? currency;
}
