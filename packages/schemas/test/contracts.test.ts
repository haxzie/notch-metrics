import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import * as S from "../src/index.ts";

const FIXTURE_DIR = join(import.meta.dirname, "..", "..", "..", "contracts", "fixtures");

const BY_NAME: Record<string, z.ZodType> = {
  "metric-series": S.MetricResult,
  "metric-series-empty": S.MetricResult,
  "metric-series-no-currency": S.MetricResult,
  "metric-series-list": S.MetricResult,
  "metric-series-ci": S.MetricResult,
  "metric-error": S.MetricResult,
  "metric-batch": S.MetricBatchResponse,
  "provider-manifest-list": S.ProviderManifestList,
  integration: S.Integration,
  "widget-layout": S.WidgetLayout,
  "latest-json": S.LatestJson,
  "plugin-manifest": S.PluginManifest,
  "connector-manifest": S.LocalConnectorManifest,
  "notification-feed": S.NotificationFeed,
  "notification-feed-empty": S.NotificationFeed,
  "notification-feed-truncated": S.NotificationFeed,
  "notification-settings": S.NotificationSettings,
};

describe("committed contract fixtures", () => {
  const files = readdirSync(FIXTURE_DIR).filter((f) => f.endsWith(".json"));

  it("has at least one fixture", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    const name = file.replace(/\.json$/, "");
    it(`${name} parses, and re-parses identically`, () => {
      const schema = BY_NAME[name];
      expect(schema, `no schema registered for fixture ${name}`).toBeDefined();

      const raw: unknown = JSON.parse(readFileSync(join(FIXTURE_DIR, file), "utf8"));
      const parsed = schema!.parse(raw);

      // The fixture is emitted post-parse, so parsing must be a no-op. If it is
      // not, a zod default is being applied at read time — which Swift, having
      // no notion of the default, would decode differently.
      expect(parsed).toEqual(raw);
    });
  }
});

describe("wire enums", () => {
  it("rejects an unknown metric error code", () => {
    // The Swift side decodes enums with an `unknown` fallback so an old app
    // survives a new code. The *server* side must stay strict, or a typo in a
    // route handler ships as a valid-looking payload.
    expect(S.MetricErrorCode.safeParse("teapot").success).toBe(false);
  });

  it("rejects an unknown notification type and severity", () => {
    // Same asymmetry as above: the Mac falls back, the server does not. A
    // provider inventing a type id must fail here rather than ship a row no
    // installed app has copy for.
    expect(S.NotificationTypeId.safeParse("a_type_from_the_future").success).toBe(false);
    expect(S.NotificationSeverity.safeParse("apocalyptic").success).toBe(false);
  });
});

describe("pricing", () => {
  it("states the two plans the website and the app both quote", () => {
    expect(S.PLANS.pro.amount).toBe(900);
    expect(S.PLANS.pro.interval).toBe("month");
    expect(S.PLANS.pro_annual.amount).toBe(4900);
    expect(S.PLANS.pro_annual.interval).toBe("year");
    // Minor units, like every other amount that crosses this wire.
    expect(Number.isInteger(S.PLANS.pro.amount)).toBe(true);
    expect(Number.isInteger(S.PLANS.pro_annual.amount)).toBe(true);
  });

  it("drops the decimals on a whole amount", () => {
    expect(S.formatPrice(900, "USD")).toBe("$9");
    expect(S.formatPrice(4900, "USD")).toBe("$49");
    // And keeps them when there is something to show, so a future
    // $19.50 does not silently render as $20.
    expect(S.formatPrice(1950, "USD")).toBe("$19.50");
  });

  it("quotes the annual saving against twelve monthly payments", () => {
    expect(S.annualSavingPercent()).toBe(55);
  });

  it("only offers plans the checkout route accepts", () => {
    for (const plan of Object.values(S.PLANS)) {
      expect(S.CheckoutRequest.parse({ plan: plan.id }).plan).toBe(plan.id);
    }
  });
});
