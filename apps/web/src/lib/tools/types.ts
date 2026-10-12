import type { FaqEntry } from "@/lib/faq";

/**
 * The shape of a free calculator.
 *
 * Plain data plus one pure `compute`, with no React and no `node:` import, so
 * the same module is read by the server page for its metadata and imported
 * directly by the client calculator. The function never crosses the
 * server-to-client boundary as a prop, which it could not: the client
 * component looks the tool up by slug instead.
 */

export type ToolCategory = "saas" | "commerce" | "marketing" | "payments";

export const CATEGORY_LABELS: Record<ToolCategory, string> = {
  saas: "Subscription metrics",
  commerce: "Commerce",
  marketing: "Marketing and audience",
  payments: "Payments",
};

export const CATEGORY_ORDER: ToolCategory[] = ["saas", "commerce", "marketing", "payments"];

/**
 * What a number means, which decides how it is parsed and how it is shown.
 *
 * `money` is held in **integer minor units** everywhere inside a tool, the
 * same as it is everywhere else in this codebase. The input renders major
 * units because that is what somebody types, and converts on the way in. A
 * fee calculator that drifts by a penny is a fee calculator nobody trusts.
 *
 * `percent` is the number as typed, so `2.9` means 2.9%. Dividing by a
 * hundred is the compute function's job, which keeps the input and the label
 * agreeing.
 */
export type Unit = "money" | "count" | "percent" | "months";

export type ToolField = {
  key: string;
  label: string;
  unit: Unit;
  /** Minor units for `money`, otherwise the number as typed. */
  default: number;
  help?: string;
  min?: number;
  step?: number;
};

export type ToolOutput = {
  key: string;
  label: string;
  unit: Unit;
  /** The headline figure. Exactly one output per tool sets this. */
  primary?: boolean;
  help?: string;
};

/** `null` means the inputs cannot produce an answer, such as a zero divisor. */
export type ComputeResult = Record<string, number | null>;

/**
 * A field's current value, by key.
 *
 * A callable rather than a `Record`, because `noUncheckedIndexedAccess` is on
 * and indexing a record yields `number | undefined` on every single read. The
 * accessor is the one place that fallback lives, which is the same reason the
 * test suites have `scalar()`.
 */
export type ToolValues = (key: string) => number;

export type ToolSection = { heading: string; paragraphs: string[] };

export type Tool = {
  slug: string;
  /** "MRR calculator". Used in the index, the breadcrumb and the OG card. */
  name: string;
  category: ToolCategory;
  /** The `<h1>`, which is allowed to be longer than the name. */
  heading: string;
  /** Meta description. The registry throws above 160 characters at build. */
  description: string;
  lede: string;
  /** The formula in one line, shown under the calculator. */
  formula: string;
  fields: ToolField[];
  outputs: ToolOutput[];
  compute: (v: ToolValues) => ComputeResult;
  /** The prose. This is what makes the page worth indexing. */
  sections: ToolSection[];
  faq: FaqEntry[];
  related: { label: string; href: string }[];
};

/** A divisor that would produce Infinity or NaN. */
export function safeDivide(numerator: number, denominator: number): number | null {
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) {
    return null;
  }
  const result = numerator / denominator;
  return Number.isFinite(result) ? result : null;
}
