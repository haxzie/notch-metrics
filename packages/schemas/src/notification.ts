import { z } from "zod";
import { IntegrationId, MetricId, NotificationTypeId } from "./ids.ts";
import { CurrencyCode } from "./money.ts";

/**
 * Notification delivery shapes — what the Worker hands the Mac.
 *
 * The *declaration* side lives in `manifest.ts` beside `MetricDescriptor`,
 * because a notification type is a manifest field. This file is the other half:
 * the rows themselves, the feed envelope, and the subscription state.
 *
 * The enums at the top live here rather than in `manifest.ts` so that
 * `metric.ts` can import `NotificationCursor` for the batch ride-along without
 * creating an import cycle through the manifest.
 */

export const NotificationKind = z.enum(["event", "threshold"]);
export type NotificationKind = z.infer<typeof NotificationKind>;

export const NotificationSeverity = z.enum(["info", "success", "warning"]);
export type NotificationSeverity = z.infer<typeof NotificationSeverity>;

export const NotificationComparator = z.enum([
  "above",
  "below",
  "pct_change_up",
  "pct_change_down",
]);
export type NotificationComparator = z.infer<typeof NotificationComparator>;

/**
 * One delivered notification.
 *
 * `provider` and `connectionLabel` are denormalised onto the row on purpose.
 * The underlying integration is `SET NULL` on disconnect — "Stripe payment
 * received" is still a true thing to have been told after Stripe is gone, and a
 * notification centre that empties itself on disconnect reads as data loss — so
 * the row has to be able to group and render itself with no integration behind
 * it. Same reasoning as `widget.appId`.
 */
export const Notification = z.object({
  id: z.string(),
  /**
   * Per-user monotonic. **A cursor, not a sort key.**
   *
   * Sort on `occurredAt`. A notification found by a later evaluation can carry
   * a higher `seq` than an older one it discovered alongside, so sorting on
   * `seq` produces a feed in apparently random order — a bug that is easy to
   * write and hard to read.
   */
  seq: z.number().int(),
  integrationId: IntegrationId.nullable(),
  provider: z.string(),
  connectionLabel: z.string(),
  typeId: NotificationTypeId,
  severity: NotificationSeverity,
  title: z.string(),
  body: z.string().nullable(),
  /** Minor units of `currency`. Never a float. */
  amount: z.number().int().nullable(),
  currency: CurrencyCode.nullable(),
  /**
   * Where clicking this goes, in the provider's own dashboard.
   *
   * Validated against the provider manifest's `allowedHosts` before it is ever
   * stored, because the Mac hands it straight to `NSWorkspace`.
   */
  url: z.url().nullable(),
  /** When the thing happened. **The sort key.** */
  occurredAt: z.string(),
  /** When we found out. The gap between the two is the latency the user feels. */
  createdAt: z.string(),
  read: z.boolean().default(false),
  /**
   * False inside quiet hours, or when the master switch is off: file it, do not
   * raise it. Decided server-side so two Macs agree about what was quiet.
   */
  alert: z.boolean().default(true),
});
export type Notification = z.infer<typeof Notification>;

/**
 * A row of the notification centre's sidebar.
 *
 * A separate array from `items` because a connection with zero notifications
 * still has to appear in the sidebar — which a flat list of rows cannot say.
 */
export const NotificationConnectionSummary = z.object({
  integrationId: IntegrationId.nullable(),
  provider: z.string(),
  label: z.string(),
  unread: z.number().int(),
  total: z.number().int(),
});
export type NotificationConnectionSummary = z.infer<typeof NotificationConnectionSummary>;

/**
 * The cheap poll's whole answer, and the batch ride-along.
 *
 * One primary-key read of `notification_state`. The client learns "there is
 * news" for a few hundred bytes and only then spends a request on the feed.
 */
export const NotificationCursor = z.object({
  seq: z.number().int(),
  unread: z.number().int(),
  /**
   * How long the client should wait before asking again — a **floor** on
   * whatever its own power state wants.
   *
   * The server sets it because only the server knows the cron's stagger. A user
   * with nothing enabled gets an hour and stops polling; polling faster than
   * the cron evaluates produces literally nothing.
   */
  pollAfterSeconds: z.number().int(),
});
export type NotificationCursor = z.infer<typeof NotificationCursor>;

/**
 * One page of the feed.
 *
 * Two different reads share this envelope, and they are not the same query:
 *
 *   - **live sync** — `?since=<seq>`, "everything newer than my cursor". What
 *     the poll does, and what advances `seq`.
 *   - **history** — `?before=<seq>`, "the page older than this". What the pane
 *     does when the user scrolls, and what a fresh install does to backfill.
 *
 * Both are served by the `(user_id, seq)` index. `seq` is the cursor for the
 * first and `oldestSeq` the cursor for the second, which is why both are on the
 * envelope rather than one doing double duty — a client cannot derive either
 * from `items` when `items` is empty.
 */
export const NotificationFeed = z.object({
  /** The caller's next `?since=`: the highest seq that exists, not the highest
   *  returned. Advancing it on a `before` page would skip unseen rows. */
  seq: z.number().int(),
  unread: z.number().int(),
  /** Newest first, by `occurredAt`. */
  items: z.array(Notification),
  connections: z.array(NotificationConnectionSummary),
  /**
   * Whether older rows exist beyond this page — `?before=<oldestSeq>` fetches
   * them.
   *
   * Distinct from `truncated` on purpose. This one is about the *archive* and
   * invites another request; that one is about *banners* and suppresses them.
   * Collapsing the two would make a long scroll suppress toasts, and a quiet
   * catch-up look like the end of the list.
   */
  hasMore: z.boolean().default(false),
  /** The lowest seq in `items`, i.e. the next `?before=`. Null on an empty
   *  page, which is the case a client would otherwise derive as 0 and then
   *  re-request the whole archive forever. */
  oldestSeq: z.number().int().nullable().default(null),
  /**
   * The *live-sync* gap was wider than one page, so the client fills the centre
   * but collapses its banners to a single summary rather than firing one per
   * row. Never set on a history page — scrolling back is not news.
   */
  truncated: z.boolean().default(false),
  pollAfterSeconds: z.number().int(),
});
export type NotificationFeed = z.infer<typeof NotificationFeed>;

export const NotificationThreshold = z.object({
  metric: MetricId,
  comparator: NotificationComparator,
  /** Minor units when the metric is currency; percent for a `pct_` comparator. */
  value: z.number(),
});
export type NotificationThreshold = z.infer<typeof NotificationThreshold>;

export const NotificationSubscription = z.object({
  id: z.string(),
  integrationId: IntegrationId,
  typeId: NotificationTypeId,
  enabled: z.boolean(),
  params: z.record(z.string(), z.string()).default({}),
  /** Threshold types only. Null for events. */
  threshold: NotificationThreshold.nullable().default(null),
  minIntervalSeconds: z.number().int(),
});
export type NotificationSubscription = z.infer<typeof NotificationSubscription>;

export const NotificationSettings = z.object({
  /**
   * Optimistic-concurrency token, the `widget_revision` pattern — but note the
   * direction is **inverted**. The Mac is authoritative for a widget layout;
   * the *server* is authoritative here, because the server is the evaluator and
   * a muted type it never generates is bytes never sent and a wake never taken.
   * The Mac holds a cache, not the truth.
   */
  revision: z.number().int(),
  /** Master switch. Off means the evaluator skips the user entirely. */
  enabled: z.boolean(),
  /**
   * Local minutes from midnight in the user's timezone, or null for none.
   *
   * Minutes rather than a timestamp: a quiet-hours instant persisted across a
   * timezone change means quiet hours silently move.
   */
  quietFromMinute: z.number().int().min(0).max(1439).nullable(),
  quietToMinute: z.number().int().min(0).max(1439).nullable(),
  subscriptions: z.array(NotificationSubscription),
});
export type NotificationSettings = z.infer<typeof NotificationSettings>;

export const NotificationReadRequest = z
  .object({
    /** Mark everything up to and including this `seq`. */
    upToSeq: z.number().int().optional(),
    ids: z.array(z.string()).max(200).optional(),
  })
  .refine((v) => v.upToSeq !== undefined || v.ids !== undefined, {
    message: "Provide upToSeq or ids.",
  });
export type NotificationReadRequest = z.infer<typeof NotificationReadRequest>;

/**
 * The feed query.
 *
 * `since` and `before` are mutually exclusive: one walks forward from a cursor
 * and the other backward from one, and a request carrying both is a caller that
 * has not decided which it wants.
 */
export const NotificationFeedQuery = z
  .object({
    since: z.coerce.number().int().min(0).optional(),
    before: z.coerce.number().int().min(1).optional(),
    /**
     * Capped at 100. The notch pane shows about seven rows at a time, so a
     * bigger page buys nothing and an uncapped one is a way to ask D1 for
     * somebody's entire archive in one request.
     */
    limit: z.coerce.number().int().min(1).max(100).default(50),
    integrationId: IntegrationId.optional(),
  })
  .refine((v) => v.since === undefined || v.before === undefined, {
    message: "Provide since or before, not both.",
  });
export type NotificationFeedQuery = z.infer<typeof NotificationFeedQuery>;
