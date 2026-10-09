/**
 * Writes `contracts/jsonschema/*.json` and `contracts/fixtures/*.json`.
 *
 * Both directories are committed, and CI runs this followed by
 * `git diff --exit-code contracts/`. That turns an unintentional wire-shape
 * change into a failing build rather than a surprise, and the fixtures are what
 * `apps/mac/Kit/Tests/ContractTests` decodes — so a renamed field fails the
 * Swift suite by name instead of failing at a user's launch.
 */
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import * as S from "../src/index.ts";

const ROOT = join(import.meta.dirname, "..", "..", "..", "contracts");
const SCHEMA_DIR = join(ROOT, "jsonschema");
const FIXTURE_DIR = join(ROOT, "fixtures");

const SCHEMAS: Record<string, z.ZodType> = {
  MetricSeries: S.MetricSeries,
  MetricResult: S.MetricResult,
  MetricBatchResponse: S.MetricBatchResponse,
  MetricCatalogEntry: S.MetricCatalogEntry,
  ProviderManifest: S.ProviderManifest,
  ProviderManifestList: S.ProviderManifestList,
  Integration: S.Integration,
  VerifyResponse: S.VerifyResponse,
  Widget: S.Widget,
  WidgetLayout: S.WidgetLayout,
  BillingState: S.BillingState,
  MeResponse: S.MeResponse,
  DesktopTokenResponse: S.DesktopTokenResponse,
  PluginManifest: S.PluginManifest,
  PluginRunResult: S.PluginRunResult,
  LatestJson: S.LatestJson,
};

const AT = "2026-10-05T12:00:00.000Z";

const series: S.MetricSeries = {
  integrationId: "int_4f2a9c",
  metric: "mrr",
  unit: "currency",
  currency: "USD",
  value: 1_284_500,
  previousValue: 1_190_000,
  delta: { absolute: 94_500, percent: 7.94 },
  points: [
    { t: "2026-09-05T00:00:00.000Z", v: 1_190_000 },
    { t: "2026-09-20T00:00:00.000Z", v: 1_236_000 },
    { t: "2026-10-05T00:00:00.000Z", v: 1_284_500 },
  ],
  granularity: "day",
  range: "30d",
  from: "2026-09-05T00:00:00.000Z",
  to: AT,
  format: { decimals: 0, compact: true, prefix: "", suffix: "" },
  generatedAt: AT,
  stale: false,
};

const manifest: S.ProviderManifest = {
  id: "stripe",
  name: "Stripe",
  category: "revenue",
  tagline: "Revenue, MRR and subscribers from your Stripe account.",
  docsUrl: "https://dashboard.stripe.com/apikeys",
  iconPath: "/providers/stripe.svg",
  accentColor: "#635BFF",
  authMode: "api_key",
  fields: [
    {
      key: "secret_key",
      label: "Secret key",
      type: "secret",
      required: true,
      placeholder: "rk_live_…",
      help: "A restricted key with read access to Charges and Subscriptions is enough.",
      pattern: "^(sk|rk)_(live|test)_[A-Za-z0-9]+$",
    },
  ],
  metrics: [
    {
      id: "mrr",
      label: "Monthly recurring revenue",
      shortLabel: "MRR",
      unit: "currency",
      granularities: ["day", "week", "month"],
      supportsSeries: false,
      supportsCompare: true,
      methodology:
        "Active subscriptions at the end of the window, each normalised to a monthly amount and reduced by any percentage coupon.",
    },
  ],
  allowedHosts: ["api.stripe.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};

/**
 * Edge cases matter more than the happy path here. Each of these has broken a
 * decoder somewhere: a null currency, an empty series, a stale envelope, and an
 * error carried inside a 200.
 */
const FIXTURES: Record<string, unknown> = {
  "metric-series": { ok: true, series },
  "metric-series-empty": {
    ok: true,
    series: { ...series, points: [], previousValue: null, delta: null, stale: true },
  },
  "metric-series-no-currency": {
    ok: true,
    series: { ...series, unit: "count", currency: null, value: 412, format: null },
  },
  "metric-series-list": {
    ok: true,
    series: {
      ...series,
      metric: "recent_payments",
      value: 14_900,
      previousValue: null,
      delta: null,
      points: [{ t: AT, v: 14_900 }],
      items: [
        {
          id: "ch_1",
          t: "2026-10-05T11:42:00.000Z",
          label: "Ada Lovelace",
          detail: "Pro · yearly",
          amount: 9_900,
          currency: "USD",
          status: "succeeded",
        },
        {
          id: "ch_2",
          t: "2026-10-05T09:10:00.000Z",
          label: "grace@example.com",
          detail: null,
          amount: 5_000,
          currency: "USD",
          status: "refunded",
        },
        {
          id: "ch_3",
          t: "2026-10-04T22:05:00.000Z",
          label: "Linus",
          detail: "Team seat",
          amount: null,
          currency: null,
          status: null,
        },
      ],
    },
  },
  "metric-error": {
    ok: false,
    integrationId: "int_4f2a9c",
    metric: "mrr",
    code: "rate_limited",
    message: "Stripe asked us to wait 30 seconds.",
    retryAfterSeconds: 30,
  },
  "metric-batch": {
    results: [
      { ok: true, series },
      {
        ok: false,
        integrationId: "int_b71e02",
        metric: "revenue",
        code: "auth_failed",
        message: "That key was revoked. Reconnect the integration.",
        retryAfterSeconds: null,
      },
    ],
  },
  "provider-manifest-list": { version: "2026-10-05.1", providers: [manifest] },
  integration: {
    id: "int_4f2a9c",
    provider: "stripe",
    label: "Acme Inc",
    status: "ok",
    credentialHint: "rk_live_…4f2a",
    accountLabel: "acct_1Nx · Acme Inc",
    accountCurrency: "USD",
    enabledMetrics: ["mrr", "revenue"],
    availableMetrics: ["mrr", "revenue", "active_subscribers"],
    lastSyncedAt: AT,
    lastErrorAt: null,
    lastErrorCode: null,
    createdAt: AT,
  },
  "widget-layout": {
    revision: 7,
    rows: 2,
    display: "grid",
    widgets: [
      {
        id: "wid_01",
        kind: "provider_metric",
        appId: "stripe",
        integrationId: "int_4f2a9c",
        metric: "mrr",
        customMetricId: null,
        title: "MRR",
        // A non-empty one on purpose: an empty map decodes under almost any
        // mistake, so the fixture that proves the Swift side reads per-widget
        // parameters has to carry one.
        params: { repository: "haxzie/notch-metrics" },
        size: "2x2",
        col: 0,
        row: 0,
        position: 0,
        granularity: "day",
        range: "30d",
        chart: "sparkline",
        visible: true,
      },
      {
        id: "wid_02",
        kind: "custom_metric",
        appId: "github",
        integrationId: null,
        metric: null,
        customMetricId: "github-stars",
        title: "Stars",
        size: "1x1",
        col: 2,
        row: 0,
        position: 1,
        granularity: "day",
        range: "30d",
        chart: "none",
        visible: true,
      },
    ],
  },
  // The list view, with three apps represented — what the Swift decoder has
  // to cope with when it groups rows by app.
  "latest-json": {
    version: "0.2.0",
    build: 412,
    tag: "mac-v0.2.0",
    publishedAt: AT,
    platform: "darwin-arm64",
    minimumSystemVersion: "14.0",
    filename: "NotchMetrics-0.2.0-arm64.dmg",
    url: "https://assets.notchmetrics.com/desktop/0.2.0/NotchMetrics-0.2.0-arm64.dmg",
    size: 18_234_112,
    sha256: "e".repeat(64),
    notes: "https://github.com/haxzie/notch-metrics/releases/tag/mac-v0.2.0",
    mandatory: false,
  },
  "plugin-manifest": {
    schemaVersion: 1,
    id: "github-stars",
    name: "GitHub stars",
    shortLabel: "Stars",
    description: "Stargazers on a repository.",
    appId: "github",
    unit: "count",
    format: { decimals: 0, compact: true, prefix: "", suffix: "" },
    granularities: ["day"],
    supportsSeries: false,
    refreshIntervalSeconds: 900,
    secrets: [
      {
        key: "GITHUB_TOKEN",
        label: "GitHub token",
        help: "A classic token with no scopes.",
        required: true,
      },
    ],
    allowedHosts: ["api.github.com"],
    timeoutMs: 8000,
    entry: "metric.mjs",
    author: "claude-code",
    createdAt: AT,
    updatedAt: AT,
  },
};

const FIXTURE_SCHEMA: Record<keyof typeof FIXTURES & string, z.ZodType> = {
  "metric-series": S.MetricResult,
  "metric-series-empty": S.MetricResult,
  "metric-series-no-currency": S.MetricResult,
  "metric-series-list": S.MetricResult,
  "metric-error": S.MetricResult,
  "metric-batch": S.MetricBatchResponse,
  "provider-manifest-list": S.ProviderManifestList,
  integration: S.Integration,
  "widget-layout": S.WidgetLayout,
  "latest-json": S.LatestJson,
  "plugin-manifest": S.PluginManifest,
};

function writeSorted(dir: string, name: string, value: unknown) {
  writeFileSync(join(dir, `${name}.json`), `${JSON.stringify(value, null, 2)}\n`);
}

function main() {
  for (const dir of [SCHEMA_DIR, FIXTURE_DIR]) {
    rmSync(dir, { recursive: true, force: true });
    mkdirSync(dir, { recursive: true });
  }

  for (const [name, schema] of Object.entries(SCHEMAS)) {
    writeSorted(SCHEMA_DIR, name, z.toJSONSchema(schema, { io: "output" }));
  }

  for (const [name, value] of Object.entries(FIXTURES)) {
    // Emit the *parsed* value, so defaults are materialised. A fixture that
    // relies on a zod default is a fixture the Swift decoder cannot read,
    // because Swift has no idea what the default was.
    const parsed = FIXTURE_SCHEMA[name]!.parse(value);
    writeSorted(FIXTURE_DIR, name, parsed);
  }

  const counts = [SCHEMA_DIR, FIXTURE_DIR].map((d) => readdirSync(d).length);
  console.log(`wrote ${counts[0]} schemas and ${counts[1]} fixtures to contracts/`);
}

main();
