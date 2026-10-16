import { index, integer, real, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
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

/**
 * A pending connect flow: the app asked for a link, the browser has not
 * finished with it yet.
 *
 * Short-lived and single-use. Only the hash is stored — the plaintext travels
 * in a URL, and a leaked log or browser history should not be enough to
 * resume somebody else's connection.
 */
export const connectLink = sqliteTable(
  "connect_link",
  {
    id: text("id").primaryKey(),
    tokenHash: text("token_hash").notNull().unique(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    connectorId: text("connector_id").notNull(),
    /** OAuth state, signed into the provider redirect and checked on return. */
    oauthState: text("oauth_state"),
    /**
     * Tokens held between the OAuth callback and the user picking a property.
     * Encrypted with the same envelope as a finished integration — this row
     * is a credential for as long as it exists.
     */
    pendingCiphertext: text("pending_ciphertext"),
    pendingIv: text("pending_iv"),
    pendingWrappedDek: text("pending_wrapped_dek"),
    pendingKeyVersion: integer("pending_key_version"),
    /** Set once the flow finishes, so the app's poll can stop. */
    integrationId: text("integration_id"),
    completedAt: timestamp("completed_at"),
    expiresAt: timestamp("expires_at").notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    index("connect_link_user_idx").on(t.userId),
    index("connect_link_expiry_idx").on(t.expiresAt),
  ],
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
     * Consecutive `auth_failed` results from the *data* path. Reset on any
     * success.
     *
     * Separate from `failureCount` because they answer different questions:
     * `failureCount` drives the backoff and counts every kind of failure,
     * while this one decides whether to declare the whole connection broken.
     * A single rejected request is not evidence of that — a renamed
     * repository, a spent quota and a WAF all arrive looking like one — and
     * acting on the first one is how a working connection gets marked dead.
     */
    authFailures: integer("auth_failures").notNull().default(0),
    /**
     * When the provider said the *grant itself* is gone — revoked, expired
     * through disuse, app uninstalled. Only a human can fix it.
     *
     * The refresh sweep keys off this rather than off `status`. A row can be
     * `auth_failed` because one request was rejected while its refresh token
     * is still perfectly good; excluding those from refresh is what lets a
     * recoverable connection quietly die instead.
     */
    reauthRequiredAt: timestamp("reauth_required_at"),
    /**
     * 0..299, assigned at random on creation.
     *
     * The five-minute cron would otherwise try every integration in the account
     * on the same tick, which is a thundering herd into Stripe from one IP.
     */
    refreshOffsetSeconds: integer("refresh_offset_seconds").notNull().default(0),

    /**
     * Plaintext mirror of the `expires_at` inside the credential blob.
     *
     * Exists so the token-refresh sweep can find due rows in SQL instead of
     * decrypting every OAuth integration on every tick. Null means unknown:
     * a row from before expiry was recorded, or a connector whose tokens do
     * not expire. The sweep checks an unknown row once and the successful
     * attempt fills it in.
     */
    tokenExpiresAt: timestamp("token_expires_at"),
    /**
     * When the token endpoint was last called for this row, success or not.
     * Enforces the connector's `minIntervalMs` floor — the thing that stops a
     * bug from refreshing in a loop and getting the whole client id
     * throttled rather than one user.
     */
    lastRefreshAttemptAt: timestamp("last_refresh_attempt_at"),
    /**
     * Consecutive refresh failures that were not a dead grant. Reset on
     * success. A single provider blip must not make somebody reconnect; only
     * a run of them, with the token actually past its expiry, does.
     */
    refreshFailures: integer("refresh_failures").notNull().default(0),

    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("integration_user_idx").on(t.userId),
    index("integration_disabled_idx").on(t.disabledUntil),
    index("integration_next_allowed_idx").on(t.nextAllowedAt),
    index("integration_refresh_due_idx").on(t.provider, t.tokenExpiresAt),
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
     * The app this number comes from — "stripe", "google-analytics", or a
     * custom metric's declared app.
     *
     * Denormalised onto the widget rather than joined through `integration`,
     * because `integration_id` is SET NULL on disconnect: a widget whose
     * integration is gone still has to say which app to reconnect.
     */
    appId: text("app_id").notNull().default("unknown"),
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
  /** How tall the notch opens, in grid rows. Set by the handle on its edge. */
  rows: integer("rows").notNull().default(2),
  /** "grid" or "list". */
  display: text("display").notNull().default("grid"),
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

/**
 * What actually happened to one integration, one row per attempt.
 *
 * The columns on `integration` are single-slot: `lastErrorCode` tells you the
 * class of the most recent failure and nothing about the one before it, or
 * which request produced it. That is enough to show a tile an error and not
 * nearly enough to answer "why did this connection die", which until now
 * meant inferring it from timestamp arithmetic against a row that had already
 * been overwritten.
 *
 * Deliberately not a general application log. One row per *attempt* — a
 * metric fetch, a token refresh, a status change — not one per provider HTTP
 * call, because a metric that walks four pages would otherwise write four
 * rows for one answer. The individual calls ride along in `calls`.
 */
export const integrationEvent = sqliteTable(
  "integration_event",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    integrationId: text("integration_id")
      .notNull()
      .references(() => integration.id, { onDelete: "cascade" }),
    /** Unix seconds. Plain integer rather than a Date, so the sweep is an index scan. */
    at: integer("at").notNull(),
    /** `fetch` | `refresh` | `status` | `verify`. */
    kind: text("kind").notNull(),
    /** `ok` | `error` | `skipped`. */
    outcome: text("outcome").notNull(),
    /** Which metric this was about, when it was about one. */
    metric: text("metric"),
    /**
     * Our taxonomy — a `MetricErrorCode`, or the status a `status` row moved
     * to. The thing you filter on when asking what has been going wrong.
     */
    code: text("code"),
    /**
     * The provider's own reason, verbatim: `quotaExceeded`,
     * `bad_refresh_token`. This is the field that distinguishes a spent quota
     * from a revoked token, which our own taxonomy flattens together.
     */
    reason: text("reason"),
    /** Final HTTP status of the call that decided the outcome, when there was one. */
    httpStatus: integer("http_status"),
    durationMs: integer("duration_ms"),
    /**
     * Every provider request the attempt made: `{ host, method, status, ms }`.
     * This is what `createHttp`'s `onCall` hook has always reported and
     * nothing ever collected.
     */
    calls: json<{ host: string; method: string; status: number | null; ms: number }[]>("calls"),
    /** Redacted and bounded. Never a credential; see `redact`. */
    detail: text("detail"),
    /**
     * The HTTP request this attempt was made for, when it was made for one.
     * Null from the cron, which has no request.
     *
     * The join between the two halves of the logging: an Axiom line for a
     * slow request names an id, and this is how that id turns into the
     * provider calls it actually made.
     */
    requestId: text("request_id"),
  },
  (t) => [
    // The read path is always "this integration, newest first", so the index
    // carries `at` descending rather than making every lookup sort.
    index("integration_event_integration_idx").on(t.integrationId, t.at),
    index("integration_event_at_idx").on(t.at),
    index("integration_event_user_idx").on(t.userId),
    index("integration_event_request_idx").on(t.requestId),
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

/**
 * Per-user notification state, and the one row the Mac's cheap poll reads.
 *
 * One row per user, like `widget_revision` and for the same two reasons: the
 * counter is bumped by code Better Auth knows nothing about, and a poll on the
 * hot path has to touch exactly one primary key and no index.
 */
export const notificationState = sqliteTable("notification_state", {
  userId: text("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  /**
   * Monotonic per user, bumped with `SET seq = seq + 1 RETURNING seq`. SQLite
   * serialises writes — the same property `rate-limit.ts` already leans on —
   * so two concurrent emits cannot share a seq.
   */
  seq: integer("seq").notNull().default(0),
  /** Denormalised so the cursor poll is one row read and never a COUNT. */
  unread: integer("unread").notNull().default(0),
  /**
   * The settings' optimistic-concurrency token. Same mechanism as
   * `widget_revision.revision`, opposite direction: the server is
   * authoritative for notification settings, and the Mac holds a cache.
   */
  revision: integer("revision").notNull().default(0),
  /**
   * Master switch. Off means the evaluator skips the user entirely, which is
   * cheaper than evaluating and then discarding the result.
   */
  enabled: boolean("enabled").notNull().default(true),
  /**
   * Local minutes from midnight in `user.timezone`, or null for none.
   *
   * Minutes rather than an instant: a quiet-hours timestamp persisted across a
   * timezone change means quiet hours silently move. Inside the window a row is
   * still written and still unread — it just carries no alert, so the Mac files
   * it without raising a banner. Decided here rather than on the client so two
   * Macs agree about what was quiet.
   */
  quietFromMinute: integer("quiet_from_minute"),
  quietToMinute: integer("quiet_to_minute"),
  updatedAt: updatedAt(),
});

/** One row per (connection, notification type). The user's toggles. */
export const notificationSubscription = sqliteTable(
  "notification_subscription",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    /**
     * CASCADE, unlike `widget.integration_id`.
     *
     * A widget whose integration is gone still has to say which app to
     * reconnect. A *subscription* with no connection behind it is nothing the
     * user can act on, and the toggle is recreated from the manifest when they
     * connect again.
     */
    integrationId: text("integration_id")
      .notNull()
      .references(() => integration.id, { onDelete: "cascade" }),
    /**
     * A `NotificationTypeId`. Text rather than an enum: the catalogue is
     * served, so a provider shipping a new type must not need a migration.
     */
    typeId: text("type_id").notNull(),
    enabled: boolean("enabled").notNull().default(false),
    /**
     * Arguments the descriptor declared. Unlike a widget-scoped metric — which
     * the cron cannot warm because it knows the connection and not which
     * repository some tile points at — a subscription carries its own params,
     * so a param'd metric *is* warmable from the cron.
     */
    params: json<Record<string, string>>("params")
      .notNull()
      .$defaultFn(() => ({})),
    /** Threshold types only: `{ metric, comparator, value }`. Null for events. */
    threshold: json<{ metric: string; comparator: string; value: number }>("threshold"),
    /**
     * Re-arm floor, seeded from the descriptor so a provider can be
     * conservative without a migration.
     */
    minIntervalSeconds: integer("min_interval_seconds").notNull().default(3600),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("notification_subscription_unique_idx").on(t.integrationId, t.typeId),
    /** The cron's "which integrations owe me work?" query. */
    index("notification_subscription_enabled_idx").on(t.enabled, t.integrationId),
    index("notification_subscription_user_idx").on(t.userId),
  ],
);

/**
 * Evaluator state.
 *
 * Deliberately not columns on the subscription: a user flipping a switch must
 * never write a cursor, and the cron must never write a user's settings.
 */
export const notificationCursor = sqliteTable("notification_cursor", {
  subscriptionId: text("subscription_id")
    .primaryKey()
    .references(() => notificationSubscription.id, { onDelete: "cascade" }),
  lastEventId: text("last_event_id"),
  /**
   * Nothing older than this is news; it is history.
   *
   * On a cursor with `seenThrough` null the evaluator writes `now`, emits
   * nothing and returns. Without that, enabling a toggle delivers a month of
   * back-history at once — the single bug that would make this feature look
   * broken on the day it ships.
   */
  seenThrough: timestamp("seen_through"),
  /** Adapter-opaque, straight from `EventPage.cursor`. Never parsed by us. */
  providerCursor: text("provider_cursor"),
  /** Threshold types: the previous reading, so firing is edge-triggered. */
  lastValue: real("last_value"),
  /**
   * "above" | "below" | null. A number resting exactly on the line must not
   * fire every tick, which is what this and not `lastValue` prevents.
   */
  lastState: text("last_state"),
  firedAt: timestamp("fired_at"),
  evaluatedAt: timestamp("evaluated_at"),
});

/** A delivered notification. */
export const notification = sqliteTable(
  "notification",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    /** Per-user monotonic. Both the client's `?since=` and the ETag are this. */
    seq: integer("seq").notNull().default(0),
    /**
     * SET NULL, not CASCADE: "Stripe payment received" is still a true thing to
     * have been told after Stripe is disconnected, and a notification centre
     * that empties itself on disconnect reads as data loss.
     */
    integrationId: text("integration_id").references(() => integration.id, {
      onDelete: "set null",
    }),
    /**
     * Denormalised so a row outlives its integration and can still group and
     * render itself. Same reasoning as `widget.app_id`.
     */
    provider: text("provider").notNull(),
    connectionLabel: text("connection_label").notNull(),
    typeId: text("type_id").notNull(),
    severity: text("severity").notNull().default("info"),
    title: text("title").notNull(),
    body: text("body"),
    /** Minor units of `currency`. Never a float. */
    amount: integer("amount"),
    currency: text("currency"),
    /**
     * The provider deep link. Host-checked against the manifest's
     * `allowedHosts` before it is written, because the Mac opens it.
     */
    url: text("url"),
    /**
     * When the thing happened, not when we noticed. The UI sorts on this, and
     * the gap between the two is the latency the user actually feels.
     */
    occurredAt: timestamp("occurred_at").notNull(),
    /**
     * `<integrationId>:<typeId>:<providerEventId>` for an event,
     * `<integrationId>:<typeId>:<metric>:<direction>:<bucket>` for a threshold.
     *
     * The unique index below *is* the idempotency check — the `webhook_event`
     * pattern. The cron, a manual refresh and a later re-evaluation can all
     * find the same payment, and all but one must lose.
     */
    dedupeKey: text("dedupe_key").notNull(),
    readAt: timestamp("read_at"),
    /**
     * Whether this was allowed to interrupt: false inside the user's quiet
     * hours. The row is still written and still unread — it just gets filed
     * rather than raised.
     *
     * Decided here, server-side, rather than on the client, so two Macs agree
     * about what was quiet and a laptop in another timezone does not re-raise
     * what the desktop already filed.
     */
    alert: boolean("alert").notNull().default(true),
    /** "cron" | "internal". Diagnostics only. */
    source: text("source").notNull().default("cron"),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("notification_dedupe_idx").on(t.userId, t.dedupeKey),
    /** The feed query: everything after the client's cursor. */
    index("notification_feed_idx").on(t.userId, t.seq),
    index("notification_sweep_idx").on(t.createdAt),
  ],
);
