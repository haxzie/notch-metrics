import { describe, expect, it } from "vitest";
import { RECENT_PAYMENTS_LIMIT, recentPayments, recentPaymentsDescriptor } from "../src/list.ts";
import { MetricDescriptor } from "@notch/schemas";
import { scalar, stubContext } from "./helpers.ts";

function row(id: number, at: string, amount: number | null, currency: string | null = "USD") {
  return {
    id: `r${id}`,
    t: new Date(at),
    label: `Row ${id}`,
    detail: null,
    amount,
    currency,
    status: null,
  };
}

describe("recent payments", () => {
  it("orders newest first and caps the list", () => {
    const ctx = stubContext({});
    const rows = Array.from({ length: 15 }, (_, i) =>
      row(i, `2026-10-${String(i + 1).padStart(2, "0")}T00:00:00Z`, 100),
    );
    const series = recentPayments(ctx, rows);
    expect(series.items).toHaveLength(RECENT_PAYMENTS_LIMIT);
    expect(scalar(series.items?.[0]).id).toBe("r14");
  });

  it("totals only the user's currency, but lists every row", () => {
    const ctx = stubContext({});
    const series = recentPayments(ctx, [
      row(1, "2026-10-01T00:00:00Z", 1_000),
      row(2, "2026-10-02T00:00:00Z", 9_000, "GBP"),
      row(3, "2026-10-03T00:00:00Z", null, null),
    ]);
    expect(series.value).toBe(1_000);
    expect(series.items).toHaveLength(3);
    expect(series.unit).toBe("currency");
    expect(series.previousValue).toBeNull();
  });

  it("produces a descriptor every manifest can carry", () => {
    const descriptor = recentPaymentsDescriptor("Test.");
    expect(() => MetricDescriptor.parse(descriptor)).not.toThrow();
    expect(descriptor.supportsSeries).toBe(false);
    expect(descriptor.supportsCompare).toBe(false);
  });
});
