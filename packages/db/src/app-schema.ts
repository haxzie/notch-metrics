import { index, integer, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
import { boolean, createdAt, json, timestamp, updatedAt } from "./columns.ts";
import { user } from "./auth-schema.ts";

/** A device token the Mac app holds. Only the hash is stored. */
export const deviceToken = sqliteTable(
  "device_token",
  {
    id: text("id").primaryKey(),
    /**
     * sha256 of the bearer token.
     *
     * The plaintext exists in exactly two places: the response that minted it,
     * and the Mac's Keychain. A D1 dump therefore does not hand anybody a
     * working session.
     */
    tokenHash: text("token_hash").notNull().unique(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    label: text("label").notNull(),
    lastUsedAt: timestamp("last_used_at"),
    revokedAt: timestamp("revoked_at"),
    createdAt: createdAt(),
  },
  (t) => [index("device_token_user_idx").on(t.userId)],
);

/** One-time PKCE codes for the desktop handshake. */
export const desktopAuthCode = sqliteTable(
  "desktop_auth_code",
  {
    code: text("code").primaryKey(),
    /** base64url(SHA-256(verifier)). The verifier never reaches the server. */
    challenge: text("challenge").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    expiresAt: timestamp("expires_at").notNull(),
    /** Set in the same statement that issues the token; see routes/desktop.ts. */
    consumedAt: timestamp("consumed_at"),
    createdAt: createdAt(),
  },
  (t) => [index("desktop_auth_code_user_idx").on(t.userId)],
);

export const integration = sqliteTable(
  "integration",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    workspaceId: text("workspace_id"),
    provider: text("provider").notNull(),
    label: text("label").notNull(),

    // Envelope encryption. A random DEK per integration encrypts the
    // credentials with AES-GCM; the DEK itself is wrapped with AES-KW by a KEK
    // held as a Worker secret. Rotation re-wraps `credentialWrappedDek` and
    // never touches the ciphertext.
    credentialCiphertext: text("credential_ciphertext").notNull(),
    credentialIv: text("credential_iv").notNull(),
    credentialWrappedDek: text("credential_wrapped_dek").notNull(),
    /**
     * Which KEK generation wrapped this row's DEK.
     *
     * A column, not a global. Rotation is not atomic across rows, so code that
     * assumes the currently-active version can decrypt everything starts
     * throwing on every pre-rotation integration the moment the active version
     * is bumped.
     */
    keyVersion: integer("key_version").notNull(),
    /** First eight plus last four. Enough to tell two keys apart, not enough to be one. */
    credentialHint: text("credential_hint").notNull(),
    /** sha256 of the canonical plaintext, so the same key cannot be added twice. */
    credentialFingerprint: text("credential_fingerprint").notNull(),

    enabledMetrics: json<string[]>("enabled_metrics")
      .notNull()
      .$defaultFn(() => []),
    availableMetrics: json<string[]>("available_metrics")
      .notNull()
      .$defaultFn(() => []),
    accountLabel: text("account_label"),
    accountCurrency: text("account_currency"),

    status: text("status").notNull().default("ok"),
    lastErrorCode: text("last_error_code"),
    lastErrorAt: timestamp("last_error_at"),
    lastSyncedAt: timestamp("last_synced_at"),

    // Outbound throttle and circuit breaker. `nextAllowedAt` spaces calls for
    // one integration so a five-metric batch does not fan out into five
    // concurrent page walks; `disabledUntil` is the breaker, and `auth_failed`
    // stops polling entirely — hammering a revoked key every five minutes
    // forever is how an account gets its IP blocked.
    nextAllowedAt: integer("next_allowed_at").notNull().default(0),
    failureCount: integer("failure_count").notNull().default(0),
    disabledUntil: integer("disabled_until").notNull().default(0),
    /**
     * 0..299, assigned at random on creation.
     *
     * The five-minute cron would otherwise try every integration in the account
     * on the same tick, which is a thundering herd into Stripe from one IP.
     */
    refreshOffsetSeconds: integer("refresh_offset_seconds").notNull().default(0),

    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("integration_user_idx").on(t.userId),
    index("integration_disabled_idx").on(t.disabledUntil),
    index("integration_next_allowed_idx").on(t.nextAllowedAt),
    uniqueIndex("integration_fingerprint_idx").on(t.userId, t.provider, t.credentialFingerprint),
  ],
);

export const widget = sqliteTable(
  "widget",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    workspaceId: text("workspace_id"),
    kind: text("kind").notNull(),
    /**
     * SET NULL rather than CASCADE.
     *
     * Disconnecting Stripe should leave a tile saying "reconnect Stripe" where
     * it was, not silently rearrange the user's notch behind their back.
     */
    integrationId: text("integration_id").references(() => integration.id, {
      onDelete: "set null",
    }),
    metric: text("metric"),
    /** A local plugin id. The definition lives on the Mac, not here. */
    customMetricId: text("custom_metric_id"),
    title: text("title"),
    size: text("size").notNull().default("2x1"),
    col: integer("col").notNull().default(0),
    row: integer("row").notNull().default(0),
    position: integer("position").notNull(),
    granularity: text("granularity").notNull().default("day"),
    range: text("range").notNull().default("30d"),
    chart: text("chart").notNull().default("sparkline"),
    visible: boolean("visible").notNull().default(true),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("widget_user_visible_idx").on(t.userId, t.visible),
    uniqueIndex("widget_position_idx").on(t.userId, t.position),
  ],
);

/**
 * One row per user: the optimistic-concurrency token for the layout backup.
 *
 * A column on `user` would mean adding a field to a Better Auth table for
 * something Better Auth knows nothing about, and every bump would write a row
 * that the auth layer also writes.
 */
export const widgetRevision = sqliteTable("widget_revision", {
  userId: text("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  revision: integer("revision").notNull().default(0),
  updatedAt: updatedAt(),
});

export const metricCache = sqliteTable(
  "metric_cache",
  {
    /** `<integrationId>:<metric>:<granularity>:<range>` */
    cacheKey: text("cache_key").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    integrationId: text("integration_id")
      .notNull()
      .references(() => integration.id, { onDelete: "cascade" }),
    /** A whole MetricEnvelope, served verbatim on a hit. */
    payload: text("payload").notNull(),
    etag: text("etag").notNull(),
    computedAt: integer("computed_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
    source: text("source").notNull().default("request"),
  },
  (t) => [
    index("metric_cache_user_idx").on(t.userId),
    index("metric_cache_expiry_idx").on(t.expiresAt),
    index("metric_cache_integration_idx").on(t.integrationId),
  ],
);

/** Fixed-window counters. `subject` is "user:<id>" | "device:<id>" | "ip:<hash>" | … */
export const rateLimit = sqliteTable(
  "rate_limit",
  {
    subject: text("subject").notNull(),
    windowStart: integer("window_start").notNull(),
    count: integer("count").notNull().default(0),
  },
  (t) => [uniqueIndex("rate_limit_subject_idx").on(t.subject, t.windowStart)],
);

export const subscription = sqliteTable(
  "subscription",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .unique()
      .references(() => user.id, { onDelete: "cascade" }),
    dodoSubscriptionId: text("dodo_subscription_id").unique(),
    dodoCustomerId: text("dodo_customer_id"),
    status: text("status").notNull().default("trialing"),
    currentPeriodEnd: timestamp("current_period_end"),
    /** A failed renewal keeps access until here before the plan drops. */
    graceUntil: timestamp("grace_until"),
    cancelAtPeriodEnd: boolean("cancel_at_period_end").notNull().default(false),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("subscription_customer_idx").on(t.dodoCustomerId)],
);

/**
 * Delivered webhook ids.
 *
 * The insert *is* the idempotency check — a primary-key conflict means we have
 * seen this delivery. `payment.succeeded` fires for renewals as well as first
 * payments, and Dodo retries, so "have I already handled this?" is not optional.
 */
export const webhookEvent = sqliteTable("webhook_event", {
  id: text("id").primaryKey(),
  type: text("type").notNull(),
  createdAt: createdAt(),
});
