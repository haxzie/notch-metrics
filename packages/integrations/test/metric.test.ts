import { describe, expect, it } from "vitest";
import { z } from "zod";
import { MetricDescriptor, type ProviderManifest } from "@notch/schemas";
import { listMetric, provider, scalarMetric, seriesMetric, toDescriptor } from "../src/metric.ts";
import { stubContext } from "./helpers.ts";

const creds = z.object({ token: z.string() });
type Creds = z.infer<typeof creds>;

const base = {
  label: "Thing",
  shortLabel: "Thing",
  unit: "count" as const,
  methodology: "A thing.",
};

const stars = scalarMetric<Creds>({
  ...base,
  id: "stars",
  async fetch() {
    return { value: 7 };
  },
});

const visitors = seriesMetric<Creds>({
  ...base,
  id: "visitors",
  granularities: ["day", "week"],
  compare: true,
  async fetch(ctx) {
    return { points: [{ t: ctx.now(), v: 3 }], value: 3, previousValue: 1 };
  },
});

const payments = listMetric<Creds>({
  ...base,
  id: "recent_payments",
  limit: 10,
  async fetch(ctx) {
    return {
      items: [
        {
          id: "a",
          t: ctx.now(),
          label: "A",
          detail: null,
          amount: 100,
          currency: "usd",
          status: null,
        },
        {
          id: "b",
          t: ctx.now(),
          label: "B",
          detail: null,
          amount: 200,
          currency: "usd",
          status: null,
        },
      ],
    };
  },
});

const MANIFEST = {
  id: "github",
  name: "GitHub",
  category: "developer",
  tagline: "t",
  docsUrl: "https://example.com",
  iconPath: "/connectors/github.svg",
  accentColor: "#181717",
  authMode: "api_key",
  fields: [],
  allowedHosts: ["api.github.com"],
  status: "stable",
  minAppVersion: "0.1.0",
} satisfies Omit<ProviderManifest, "metrics">;

function build(metrics: Parameters<typeof provider<Creds>>[0]["metrics"]) {
  return provider<Creds>({
    manifest: MANIFEST,
    credentialSchema: creds,
    metrics,
    async verify() {
      return { accountLabel: "acme", currency: null };
    },
  });
}

describe("the descriptor a shape derives", () => {
  it("turns each shape into the booleans the wire still carries", () => {
    expect(toDescriptor(stars)).toMatchObject({ supportsSeries: false, supportsCompare: false });
    expect(toDescriptor(visitors)).toMatchObject({
      supportsSeries: true,
      supportsCompare: true,
      granularities: ["day", "week"],
    });
    expect(toDescriptor(payments)).toMatchObject({ supportsSeries: false, supportsCompare: false });
  });

  it("parses as a MetricDescriptor, which is what the catalogue serves", () => {
    for (const metric of [stars, visitors, payments]) {
      expect(() => MetricDescriptor.parse(toDescriptor(metric))).not.toThrow();
    }
  });

  /**
   * The Range row is hidden for these, but installed apps run `clampRange()`
   * whether it is shown or not — so a narrow list here would rewrite the
   * stored range of a snapshot widget for no reason. See `toDescriptor`.
   */
  it("never narrows the ranges of a metric that has no window", () => {
    expect(toDescriptor(stars).granularities).toEqual(["hour", "day", "week", "month"]);
    expect(toDescriptor(payments).granularities).toEqual(["hour", "day", "week", "month"]);
  });
});

describe("the RawSeries a shape wraps", () => {
  const ctx = stubContext({});

  it("gives a scalar one point, at now, and no comparison", async () => {
    const series = await build([stars]).fetchMetric(
      ctx,
      { token: "t" },
      {
        metric: "stars",
        granularity: "day",
        from: new Date(0),
        to: ctx.now(),
        comparePrevious: true,
        wantSeries: true,
        params: {},
      },
    );
    expect(series.points).toEqual([{ t: ctx.now(), v: 7 }]);
    expect(series.value).toBe(7);
    expect(series.previousValue).toBeNull();
  });

  it("counts a list's rows rather than making every author do it", async () => {
    const series = await build([payments]).fetchMetric(
      ctx,
      { token: "t" },
      {
        metric: "recent_payments",
        granularity: "day",
        from: new Date(0),
        to: ctx.now(),
        comparePrevious: true,
        wantSeries: true,
        params: {},
      },
    );
    expect(series.value).toBe(2);
    expect(series.items).toHaveLength(2);
    expect(series.points).toEqual([{ t: ctx.now(), v: 2 }]);
  });
});

describe("what provider() derives", () => {
  it("lists every metric it was given, in order, as available", async () => {
    const result = await build([stars, visitors, payments]).verify(stubContext({}), {
      token: "t",
    });
    expect(result.availableMetrics).toEqual(["stars", "visitors", "recent_payments"]);
  });

  /**
   * A Stripe restricted key without the Subscriptions permission can still
   * do revenue. Narrowing is a statement about one connection, so `verify`
   * says what is *missing* rather than re-listing the catalogue — the copy
   * that used to drift.
   */
  it("withholds what one connection cannot answer", async () => {
    const narrowed = provider<Creds>({
      manifest: MANIFEST,
      credentialSchema: creds,
      metrics: [stars, visitors],
      async verify() {
        return { accountLabel: "acme", currency: null, unavailableMetrics: ["visitors"] };
      },
    });
    const result = await narrowed.verify(stubContext({}), { token: "t" });
    expect(result.availableMetrics).toEqual(["stars"]);
  });

  it("refuses a metric it was never given", async () => {
    const error = await build([stars])
      .fetchMetric(
        stubContext({}),
        { token: "t" },
        {
          metric: "mrr",
          granularity: "day",
          from: new Date(0),
          to: new Date(),
          comparePrevious: false,
          wantSeries: false,
          params: {},
        },
      )
      .catch((e: unknown) => e);
    expect((error as Error).message).toContain("does not provide mrr");
  });

  /**
   * A repeated id used to parse, because `MetricDescriptor` is a plain
   * `z.array` — and the result was two browser rows sharing a SwiftUI
   * `Identifiable` id, with the second `fetch` silently dead.
   */
  it("will not let one provider declare an id twice", () => {
    expect(() => build([stars, stars])).toThrow(/declares stars twice/);
  });
});
