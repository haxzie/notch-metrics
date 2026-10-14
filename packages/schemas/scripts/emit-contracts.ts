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
  Notification: S.Notification,
  NotificationFeed: S.NotificationFeed,
  NotificationCursor: S.NotificationCursor,
  NotificationDescriptor: S.NotificationDescriptor,
  NotificationSettings: S.NotificationSettings,
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
  iconPath: "/connectors/stripe.svg",
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
  notifications: [
    {
      id: "payment_received",
      kind: "event",
      label: "New payment",
      shortLabel: "New payment",
      severity: "success",
      methodology:
        "A charge that succeeded, seen in the recent payments list. A charge that fails and is later retried successfully arrives once, when it succeeds.",
      source: { from: "metric_items", metric: "recent_payments" },
      defaultEnabled: false,
      userConfigurable: true,
      minIntervalSeconds: 60,
      maxBurst: 5,
    },
    {
      id: "metric_threshold_crossed",
      kind: "threshold",
      label: "MRR crosses a figure",
      shortLabel: "MRR threshold",
      severity: "info",
      methodology:
        "Checked against the same monthly recurring revenue figure the tile shows, so it can be announced on a reading up to fifteen minutes old.",
      source: { from: "metric_value", metric: "mrr" },
      threshold: {
        metric: "mrr",
        comparators: ["above", "below", "pct_change_down"],
        unit: "currency",
        suggestedValue: 1_000_000,
      },
      defaultEnabled: false,
      userConfigurable: true,
      minIntervalSeconds: 3600,
      maxBurst: 1,
    },
  ],
  allowedHosts: ["api.stripe.com"],
  status: "stable",
  minAppVersion: "0.1.0",
};

const notification: S.Notification = {
  id: "ntf_7c21ab",
  seq: 412,
  integrationId: "int_4f2a9c",
  provider: "stripe",
  connectionLabel: "Acme Inc",
  typeId: "payment_received",
  severity: "success",
  title: "Payment received",
  body: "Ada Lovelace \u00b7 Pro \u00b7 yearly",
  amount: 9_900,
  currency: "USD",
  url: "https://dashboard.stripe.com/payments/ch_1",
  occurredAt: "2026-10-05T11:42:00.000Z",
  createdAt: "2026-10-05T11:44:30.000Z",
  read: false,
  alert: true,
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
  /**
   * A list whose rows carry an *outcome* rather than an amount.
   *
   * One of each state, because the tile draws a different glyph for each and
   * a fixture with only the happy one proves nothing about the other three.
   */
  "metric-series-ci": {
    ok: true,
    series: {
      ...series,
      metric: "ci_runs",
      unit: "count",
      currency: null,
      value: 4,
      previousValue: null,
      delta: null,
      format: null,
      points: [{ t: AT, v: 4 }],
      items: [
        {
          id: "101",
          t: "2026-10-05T11:42:00.000Z",
          label: "CI",
          detail: "Tell people when something happened, in the notch",
          amount: null,
          currency: null,
          status: "success",
          state: "succeeded",
        },
        {
          id: "102",
          t: "2026-10-05T11:06:00.000Z",
          label: "Deploy the API",
          detail: "Build the Mac app on the toolchain CI actually has",
          amount: null,
          currency: null,
          status: "failure",
          state: "failed",
        },
        {
          id: "103",
          t: "2026-10-05T10:01:00.000Z",
          label: "Version and publish",
          detail: "Cut 0.2.1",
          amount: null,
          currency: null,
          status: "in_progress",
          state: "running",
        },
        {
          id: "104",
          t: "2026-10-05T09:02:00.000Z",
          label: "CI",
          detail: "Search the Integrations list",
          amount: null,
          currency: null,
          status: "cancelled",
          state: "neutral",
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
  "notification-feed": {
    seq: 412,
    unread: 2,
    items: [
      notification,
      {
        // A threshold row: no amount, no currency, no provider link to open.
        ...notification,
        id: "ntf_7c21ac",
        seq: 411,
        typeId: "metric_threshold_crossed",
        severity: "info",
        title: "MRR crossed $10,000",
        body: null,
        amount: null,
        currency: null,
        url: null,
        occurredAt: "2026-10-05T09:00:00.000Z",
        createdAt: "2026-10-05T09:02:10.000Z",
      },
      {
        // Already triaged, and raised inside quiet hours so it was never
        // allowed to interrupt anybody.
        ...notification,
        id: "ntf_7c21ad",
        seq: 410,
        integrationId: null,
        typeId: "connection_broken",
        severity: "warning",
        title: "Stripe needs reconnecting",
        body: "That key was revoked.",
        amount: null,
        currency: null,
        url: null,
        occurredAt: "2026-10-04T03:15:00.000Z",
        createdAt: "2026-10-04T03:15:40.000Z",
        read: true,
        alert: false,
      },
    ],
    connections: [
      {
        integrationId: "int_4f2a9c",
        provider: "stripe",
        label: "Acme Inc",
        unread: 2,
        total: 3,
      },
    ],
    hasMore: true,
    oldestSeq: 410,
    truncated: false,
    pollAfterSeconds: 300,
  },
  // Empty `items` but a *non-empty* `connections`: a connection with nothing to
  // report still has to appear in the sidebar. This is the case that breaks a
  // sidebar decoder, and the reason it gets its own fixture.
  "notification-feed-empty": {
    seq: 0,
    unread: 0,
    items: [],
    connections: [
      {
        integrationId: "int_b71e02",
        provider: "github",
        label: "haxzie/notch-metrics",
        unread: 0,
        total: 0,
      },
    ],
    // An empty page's `oldestSeq` is null, not 0. A client that derives it as 0
    // re-requests the whole archive on every poll, forever.
    hasMore: false,
    oldestSeq: null,
    truncated: false,
    pollAfterSeconds: 3600,
  },
  "notification-feed-truncated": {
    seq: 1_300,
    unread: 183,
    items: [notification],
    connections: [
      {
        integrationId: "int_4f2a9c",
        provider: "stripe",
        label: "Acme Inc",
        unread: 183,
        total: 200,
      },
    ],
    // Both set, independently: there is more archive to walk *and* the live gap
    // was too wide to banner row by row. Collapsing them into one flag makes a
    // long scroll go silent and a quiet catch-up look like the end of the list.
    hasMore: true,
    oldestSeq: 412,
    truncated: true,
    pollAfterSeconds: 300,
  },
  "notification-settings": {
    revision: 3,
    enabled: true,
    quietFromMinute: 1_320,
    quietToMinute: 480,
    subscriptions: [
      {
        id: "nsub_01",
        integrationId: "int_4f2a9c",
        typeId: "payment_received",
        enabled: true,
        params: {},
        threshold: null,
        minIntervalSeconds: 60,
      },
      {
        // Disabled, but still carrying the bound the user typed — turning a
        // threshold back on must not lose the number.
        id: "nsub_02",
        integrationId: "int_4f2a9c",
        typeId: "metric_threshold_crossed",
        enabled: false,
        params: { account: "acct_1Nx" },
        threshold: { metric: "mrr", comparator: "below", value: 1_000_000 },
        minIntervalSeconds: 3600,
      },
    ],
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
  "metric-series-ci": S.MetricResult,
  "metric-error": S.MetricResult,
  "metric-batch": S.MetricBatchResponse,
  "provider-manifest-list": S.ProviderManifestList,
  integration: S.Integration,
  "widget-layout": S.WidgetLayout,
  "latest-json": S.LatestJson,
  "plugin-manifest": S.PluginManifest,
  "notification-feed": S.NotificationFeed,
  "notification-feed-empty": S.NotificationFeed,
  "notification-feed-truncated": S.NotificationFeed,
  "notification-settings": S.NotificationSettings,
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
