import { and, asc, desc, eq, gt, inArray, isNotNull, isNull, lt, lte, or, sql } from "drizzle-orm";
import {
  integration as integrationTable,
  notification,
  notificationCursor,
  notificationState,
  notificationSubscription,
  widget,
} from "@notch/db";
import { getAdapter } from "@notch/integrations";
import type { AdapterContext, ProviderAdapter } from "@notch/integrations";
import type {
  MetricResult,
  NotificationDescriptor,
  NotificationFeed,
  NotificationFeedQuery,
  NotificationTypeId,
} from "@notch/schemas";
import type { Database } from "./db.ts";
import { id } from "./ids.ts";

/**
 * Notification evaluation and delivery.
 *
 * **This module must never import `metrics.ts`.** The evaluator works on a
 * `MetricResult` the caller has *already* fetched — that is what makes the
 * whole feature cost zero extra provider calls, and it is also what keeps the
 * import graph acyclic, since `metrics.ts` imports `emitConnectionBroken` from
 * here.
 */

/** One page of the feed. Bigger buys nothing: the pane shows about seven rows. */
const MAX_PAGE = 100;

/** Beyond this in one live-sync gap the client collapses its banners. */
const TRUNCATE_AT = 50;

/** Nothing older than this is ever backfilled when a subscription is primed. */
const MAX_BACKFILL_MS = 24 * 60 * 60 * 1000;

const RETAIN_READ_MS = 30 * 24 * 60 * 60 * 1000;
const RETAIN_UNREAD_MS = 90 * 24 * 60 * 60 * 1000;
/** Per-user row cap. The feed is a glance and a catch-up, not an archive. */
const MAX_PER_USER = 200;

type IntegrationRow = typeof integrationTable.$inferSelect;
type SubscriptionRow = typeof notificationSubscription.$inferSelect;
type CursorRow = typeof notificationCursor.$inferSelect;

export interface Owner {
  id: string;
  timezone: string;
}

function descriptorsFor(provider: string): NotificationDescriptor[] {
  try {
    return getAdapter(provider as never).manifest.notifications ?? [];
  } catch {
    // A provider id with no adapter is a deploy problem, not a reason to abort
    // somebody's whole cron tick.
    return [];
  }
}

function descriptor(provider: string, typeId: string): NotificationDescriptor | undefined {
  return descriptorsFor(provider).find((d) => d.id === typeId);
}

/**
 * The metric a subscription needs fetched, or null if it needs none.
 *
 * A threshold's metric comes off the *subscription* rather than the descriptor,
 * because the user may have pointed it at a different metric than the
 * descriptor's suggestion.
 */
export function metricFor(provider: string, sub: SubscriptionRow): string | null {
  const d = descriptor(provider, sub.typeId);
  if (!d) return null;
  if (d.source.from === "metric_items" || d.source.from === "metric_value") {
    return sub.threshold?.metric ?? d.source.metric;
  }
  return null;
}

/**
 * Which metrics this tick owes a fetch, for the cron's priority ordering.
 *
 * These go *first* in the per-integration budget: a notification starved of its
 * input fails silently, where a cold widget merely opens a beat slower.
 */
export function requiredMetrics(provider: string, subs: readonly SubscriptionRow[]): string[] {
  const out = new Set<string>();
  for (const sub of subs) {
    const metric = metricFor(provider, sub);
    if (metric) out.add(metric);
  }
  return [...out];
}

/**
 * Params to fetch a metric with, taken from whichever subscription wants it.
 *
 * This is why a subscription can do something a widget cannot: the cron skips
 * param'd metrics because it "knows the connection, not which repository some
 * tile is pointing at", but a subscription carries its own arguments.
 */
export function paramsFor(
  provider: string,
  metric: string,
  subs: readonly SubscriptionRow[],
): Record<string, string> {
  for (const sub of subs) {
    if (metricFor(provider, sub) === metric && Object.keys(sub.params ?? {}).length > 0) {
      return sub.params;
    }
  }
  return {};
}

/**
 * Integrations the cron owes work to: those behind a visible widget, *union*
 * those behind an enabled subscription.
 *
 * Without the second half, enabling "new payment" on a connection with no tile
 * does nothing, forever, with nothing on screen to say so.
 */
export async function dueIntegrationIds(
  db: Database,
  widgetBudget: number,
  notifyBudget: number,
): Promise<string[]> {
  const byWidget = await db
    .selectDistinct({ integrationId: widget.integrationId })
    .from(widget)
    .where(and(eq(widget.visible, true), isNotNull(widget.integrationId)))
    .limit(widgetBudget);

  // A separate query with its own limit, so a user with a hundred subscriptions
  // cannot crowd widget warming out of the tick.
  const byNotify = await db
    .selectDistinct({ integrationId: notificationSubscription.integrationId })
    .from(notificationSubscription)
    .where(eq(notificationSubscription.enabled, true))
    .limit(notifyBudget);

  const ids = new Set<string>();
  for (const r of [...byWidget, ...byNotify]) {
    if (r.integrationId) ids.add(r.integrationId);
  }
  return [...ids];
}

export async function enabledSubscriptions(
  db: Database,
  integrationId: string,
): Promise<SubscriptionRow[]> {
  return db
    .select()
    .from(notificationSubscription)
    .where(
      and(
        eq(notificationSubscription.integrationId, integrationId),
        eq(notificationSubscription.enabled, true),
      ),
    );
}

/**
 * Creates the rows a connection's manifest declares, for types with no row yet.
 *
 * Insert-if-absent rather than a wipe-and-rewrite, and that is the whole
 * subtlety: adding a type to a manifest later must not retroactively opt in
 * every existing user. A type that appears after a connection existed gets
 * `defaultEnabled` at the moment that connection is next seeded — which is the
 * difference between a feature launch and a notification storm.
 */
export async function seedSubscriptions(
  db: Database,
  userId: string,
  integrationId: string,
  provider: string,
): Promise<void> {
  const descriptors = descriptorsFor(provider);
  if (descriptors.length === 0) return;

  await ensureState(db, userId);

  const existing = await db
    .select({ typeId: notificationSubscription.typeId })
    .from(notificationSubscription)
    .where(eq(notificationSubscription.integrationId, integrationId));
  const have = new Set(existing.map((r) => r.typeId));

  const rows = descriptors
    .filter((d) => !have.has(d.id))
    .map((d) => ({
      id: id("nsub"),
      userId,
      integrationId,
      typeId: d.id,
      // A threshold needs a bound only the user knows. Defaulting one on would
      // fire on day one and be wrong, so they are always off until configured.
      enabled: d.kind === "threshold" ? false : d.defaultEnabled,
      params: {},
      threshold: null,
      minIntervalSeconds: d.minIntervalSeconds,
    }));

  if (rows.length > 0) await db.insert(notificationSubscription).values(rows).onConflictDoNothing();
}

async function ensureState(db: Database, userId: string): Promise<void> {
  await db.insert(notificationState).values({ userId }).onConflictDoNothing();
}

async function cursorFor(db: Database, subscriptionId: string): Promise<CursorRow> {
  const [existing] = await db
    .select()
    .from(notificationCursor)
    .where(eq(notificationCursor.subscriptionId, subscriptionId))
    .limit(1);
  if (existing) return existing;

  await db.insert(notificationCursor).values({ subscriptionId }).onConflictDoNothing();
  const [created] = await db
    .select()
    .from(notificationCursor)
    .where(eq(notificationCursor.subscriptionId, subscriptionId))
    .limit(1);
  return created!;
}

/**
 * True when this cursor has never been evaluated, in which case the caller
 * primes it and emits nothing.
 *
 * Enabling a toggle must not deliver a month of back-history at once. That is
 * the single bug that would make this feature look broken on the day it ships.
 */
async function prime(db: Database, cursor: CursorRow): Promise<boolean> {
  if (cursor.seenThrough !== null) return false;
  await db
    .update(notificationCursor)
    .set({ seenThrough: new Date(), evaluatedAt: new Date() })
    .where(eq(notificationCursor.subscriptionId, cursor.subscriptionId));
  return true;
}

/** Local minutes from midnight in `timeZone`, for the quiet-hours comparison. */
function localMinutes(at: Date, timeZone: string): number {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(at);
    const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0");
    const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0");
    return hour * 60 + minute;
  } catch {
    // An unknown timezone must not stop a notification being delivered; it just
    // loses the user's quiet hours for that one row.
    return at.getUTCHours() * 60 + at.getUTCMinutes();
  }
}

/**
 * Whether `at` falls inside the user's quiet hours.
 *
 * Exported because the across-midnight case (22:00 to 08:00, where `from` is
 * greater than `to`) is the one everybody gets wrong, and it deserves a test
 * that does not need a database.
 */
export function inQuietHours(minutes: number, from: number | null, to: number | null): boolean {
  if (from === null || to === null) return false;
  if (from === to) return false;
  return from < to ? minutes >= from && minutes < to : minutes >= from || minutes < to;
}

export interface EmitInput {
  userId: string;
  integrationId: string | null;
  provider: string;
  connectionLabel: string;
  typeId: NotificationTypeId | string;
  severity: string;
  title: string;
  body?: string | null;
  amount?: number | null;
  currency?: string | null;
  url?: string | null;
  occurredAt: Date;
  dedupeKey: string;
  source?: "cron" | "internal";
  /** Local minutes from midnight, for quiet hours. Omit to skip the check. */
  localMinutes?: number;
}

/**
 * Writes one notification, or does nothing if we already know about it.
 *
 * The order is load-bearing: **insert first, bump second.** Bumping first would
 * let a duplicate burn a `seq` and inflate the unread count. The cost is a
 * brief window where the row sits at `seq = 0`; the feed filters `seq > 0` and
 * `?since` is exclusive, so such a row is simply not yet visible and becomes
 * visible one statement later.
 *
 * Returns the assigned `seq`, or null when the row was already known.
 */
export async function emit(db: Database, input: EmitInput): Promise<number | null> {
  await ensureState(db, input.userId);

  const [state] = await db
    .select()
    .from(notificationState)
    .where(eq(notificationState.userId, input.userId))
    .limit(1);

  // The master switch is checked here rather than at every call site, so a new
  // emitter cannot forget it.
  if (!state || !state.enabled) return null;

  const quiet =
    input.localMinutes === undefined
      ? false
      : inQuietHours(input.localMinutes, state.quietFromMinute, state.quietToMinute);

  const [inserted] = await db
    .insert(notification)
    .values({
      id: id("ntf"),
      userId: input.userId,
      seq: 0,
      integrationId: input.integrationId,
      provider: input.provider,
      connectionLabel: input.connectionLabel,
      typeId: input.typeId,
      severity: input.severity,
      title: input.title,
      body: input.body ?? null,
      amount: input.amount ?? null,
      currency: input.currency ?? null,
      url: input.url ?? null,
      occurredAt: input.occurredAt,
      dedupeKey: input.dedupeKey,
      readAt: null,
      // Inside quiet hours the row is still written and still unread — it just
      // carries no alert, so the Mac files it without raising a banner.
      alert: !quiet,
      source: input.source ?? "cron",
    })
    .onConflictDoNothing()
    .returning({ id: notification.id });

  if (!inserted) return null;

  // `SET seq = seq + 1 RETURNING seq` is safe because SQLite serialises writes
  // — the same property `rate-limit.ts` already depends on.
  const [bumped] = await db
    .update(notificationState)
    .set({
      seq: sql`${notificationState.seq} + 1`,
      unread: sql`${notificationState.unread} + 1`,
      updatedAt: new Date(),
    })
    .where(eq(notificationState.userId, input.userId))
    .returning({ seq: notificationState.seq });

  const seq = bumped?.seq ?? 0;
  await db.update(notification).set({ seq }).where(eq(notification.id, inserted.id));

  return seq;
}

/**
 * Which side of a bound a reading sits on, or null when there is no bound.
 *
 * Separated from the firing decision because *edge* detection is the whole
 * trick: a number resting exactly on the line must not fire every tick, and
 * comparing against the previous **state** rather than the previous value is
 * what prevents that.
 */
export function thresholdState(value: number, comparator: string, bound: number): string | null {
  switch (comparator) {
    case "above":
      return value > bound ? "above" : "below";
    case "below":
      return value < bound ? "above" : "below";
    default:
      return null;
  }
}

/**
 * Whether a percentage move clears the bound. Null `previous` means we have
 * nothing to compare against and therefore nothing honest to say.
 */
export function percentMove(value: number, previous: number | null): number | null {
  if (previous === null || previous === 0) return null;
  return ((value - previous) / Math.abs(previous)) * 100;
}

function hostAllowed(url: string, provider: string): boolean {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") return false;
    const hosts = getAdapter(provider as never).manifest.allowedHosts;
    return hosts.some(
      (h) =>
        parsed.hostname === h ||
        (h.startsWith("*.") && parsed.hostname.endsWith(h.slice(1))) ||
        // A provider's dashboard is not always its API host, so the
        // registrable-domain match is deliberate rather than an oversight.
        parsed.hostname.endsWith(`.${h.split(".").slice(-2).join(".")}`),
    );
  } catch {
    return false;
  }
}

/** A link the Mac will hand to `NSWorkspace`, or null if we cannot vouch for it. */
function safeUrl(url: string | null | undefined, provider: string): string | null {
  if (!url) return null;
  return hostAllowed(url, provider) ? url : null;
}

export interface EvaluateInput {
  db: Database;
  row: IntegrationRow;
  owner: Owner;
  /** Enabled subscriptions for *this metric* only. */
  subs: readonly SubscriptionRow[];
  metric: string;
  result: MetricResult;
}

/**
 * Evaluates the metric-sourced subscriptions against a series the caller has
 * already fetched. No provider call, no cache read, no integration read.
 */
export async function evaluate(input: EvaluateInput): Promise<void> {
  const { db, row, owner, subs, result } = input;
  // A failed fetch is not a notification. The connection going *dead* is, and
  // that is emitted from `recordFailure` on the edge instead.
  if (!result.ok) return;

  const series = result.series;
  const minutes = localMinutes(new Date(), owner.timezone);

  for (const sub of subs) {
    const d = descriptor(row.provider, sub.typeId);
    if (!d) continue;
    const cursor = await cursorFor(db, sub.id);
    if (await prime(db, cursor)) continue;

    if (d.source.from === "metric_items") {
      await evaluateItems({ db, row, owner, sub, d, series, minutes, cursor });
    } else if (d.source.from === "metric_value") {
      await evaluateValue({ db, row, owner, sub, d, series, minutes, cursor });
    }
  }
}

interface ArmInput {
  db: Database;
  row: IntegrationRow;
  owner: Owner;
  sub: SubscriptionRow;
  d: NotificationDescriptor;
  series: Extract<MetricResult, { ok: true }>["series"];
  minutes: number;
  cursor: CursorRow;
}

/**
 * New rows of a list metric, which is the only honest event source that costs
 * no adapter work: `MetricListItem.id` is the provider's own id, so it is a
 * real dedupe key rather than a guess.
 */
async function evaluateItems(a: ArmInput): Promise<void> {
  const { db, row, sub, d, series, minutes, cursor } = a;
  const items = series.items ?? [];
  if (items.length === 0) return;

  const floor = Math.max(cursor.seenThrough?.getTime() ?? 0, Date.now() - MAX_BACKFILL_MS);

  const fresh = items
    .filter((item) => {
      const t = Date.parse(item.t);
      return Number.isFinite(t) && t > floor;
    })
    .sort((x, y) => Date.parse(x.t) - Date.parse(y.t));

  if (fresh.length === 0) {
    await db
      .update(notificationCursor)
      .set({ evaluatedAt: new Date() })
      .where(eq(notificationCursor.subscriptionId, sub.id));
    return;
  }

  // Above `maxBurst` this collapses to one row. Seven separate notifications
  // for seven payments is seven things nobody reads.
  if (fresh.length > d.maxBurst) {
    const newest = fresh[fresh.length - 1]!;
    const total = fresh.reduce((sum, i) => sum + (i.amount ?? 0), 0);
    await emit(db, {
      userId: row.userId,
      integrationId: row.id,
      provider: row.provider,
      connectionLabel: row.accountLabel ?? row.label,
      typeId: d.id,
      severity: d.severity,
      title: `${fresh.length} ${d.shortLabel.toLowerCase()}`,
      body: null,
      amount: total > 0 ? total : null,
      currency: series.currency,
      url: null,
      occurredAt: new Date(Date.parse(newest.t)),
      // The batch is keyed on the newest id it covers, so a later tick that
      // sees the same tail does not re-announce it.
      dedupeKey: `${row.id}:${d.id}:batch:${newest.id}`,
      localMinutes: minutes,
    });
  } else {
    for (const item of fresh) {
      await emit(db, {
        userId: row.userId,
        integrationId: row.id,
        provider: row.provider,
        connectionLabel: row.accountLabel ?? row.label,
        typeId: d.id,
        severity: d.severity,
        title: d.label,
        body: [item.label, item.detail].filter(Boolean).join(" · ") || null,
        amount: item.amount,
        currency: item.currency ?? series.currency,
        url: null,
        occurredAt: new Date(Date.parse(item.t)),
        dedupeKey: `${row.id}:${d.id}:${item.id}`,
        localMinutes: minutes,
      });
    }
  }

  const newest = fresh[fresh.length - 1]!;
  await db
    .update(notificationCursor)
    .set({
      lastEventId: newest.id,
      seenThrough: new Date(Date.parse(newest.t)),
      evaluatedAt: new Date(),
      firedAt: new Date(),
    })
    .where(eq(notificationCursor.subscriptionId, sub.id));
}

/** A scalar crossing a bound the user supplied. */
async function evaluateValue(a: ArmInput): Promise<void> {
  const { db, row, sub, d, series, minutes, cursor } = a;
  const bound = sub.threshold;
  // A threshold with no bound is a toggle the user turned on and never
  // configured. Nothing to compare against, so nothing to say.
  if (!bound) return;

  const now = Date.now();
  const since = cursor.firedAt?.getTime() ?? 0;
  if (now - since < sub.minIntervalSeconds * 1000) return;

  let fired = false;
  let direction = "";

  if (bound.comparator === "above" || bound.comparator === "below") {
    const state = thresholdState(series.value, bound.comparator, bound.value);
    // Edge-triggered: fire only on the transition into `above`, never while
    // the number sits there.
    fired = state === "above" && cursor.lastState !== "above";
    direction = bound.comparator;
    await db
      .update(notificationCursor)
      .set({ lastState: state, lastValue: series.value, evaluatedAt: new Date() })
      .where(eq(notificationCursor.subscriptionId, sub.id));
  } else {
    const move = percentMove(series.value, series.previousValue);
    if (move === null) return;
    fired =
      bound.comparator === "pct_change_up" ? move >= bound.value : move <= -Math.abs(bound.value);
    direction = bound.comparator;
    await db
      .update(notificationCursor)
      .set({ lastValue: series.value, evaluatedAt: new Date() })
      .where(eq(notificationCursor.subscriptionId, sub.id));
  }

  if (!fired) return;

  const emitted = await emit(db, {
    userId: row.userId,
    integrationId: row.id,
    provider: row.provider,
    connectionLabel: row.accountLabel ?? row.label,
    typeId: d.id,
    severity: d.severity,
    title: d.label,
    body: null,
    amount: series.unit === "currency" ? Math.round(series.value) : null,
    currency: series.currency,
    url: null,
    occurredAt: new Date(),
    // The time bucket is belt and braces to the edge trigger above: the cursor
    // can be lost to a cascade, the unique index cannot.
    dedupeKey: `${row.id}:${d.id}:${bound.metric}:${direction}:${Math.floor(
      now / (sub.minIntervalSeconds * 1000),
    )}`,
    localMinutes: minutes,
  });

  if (emitted !== null) {
    await db
      .update(notificationCursor)
      .set({ firedAt: new Date() })
      .where(eq(notificationCursor.subscriptionId, sub.id));
  }
}

/**
 * Subscriptions whose source is an adapter event stream, polled once per
 * stream rather than once per subscription.
 *
 * Several notification types usually share one stream — a payments stream
 * yields both "payment failed" and "refund issued" — so polling per
 * subscription would multiply the provider calls by the number of toggles the
 * user happens to have on.
 */
/** Whether this subscription needs `fetchEvents` rather than a metric. */
export function isEventSourced(provider: string, sub: SubscriptionRow): boolean {
  return descriptor(provider, sub.typeId)?.source.from === "adapter_events";
}

export async function evaluateEvents(input: {
  db: Database;
  ctx: AdapterContext;
  credentials: Record<string, unknown>;
  row: IntegrationRow;
  owner: Owner;
  subs: readonly SubscriptionRow[];
  /** Injectable so the event path can be tested without a real provider. */
  adapter?: Pick<ProviderAdapter, "fetchEvents">;
}): Promise<void> {
  const { db, ctx, credentials, row, owner, subs } = input;
  const adapter = input.adapter ?? getAdapter(row.provider as never);
  if (!adapter.fetchEvents) return;

  const minutes = localMinutes(new Date(), owner.timezone);

  // Grouped by stream, so one poll serves every type reading it.
  const byStream = new Map<string, SubscriptionRow[]>();
  for (const sub of subs) {
    const d = descriptor(row.provider, sub.typeId);
    if (d?.source.from !== "adapter_events") continue;
    const list = byStream.get(d.source.stream) ?? [];
    list.push(sub);
    byStream.set(d.source.stream, list);
  }

  for (const [stream, group] of byStream) {
    // One cursor per stream, taken from the first subscription on it. The
    // others are read-only passengers: they decide which types to *emit*, not
    // how far the stream has been read.
    const lead = group[0]!;
    const cursor = await cursorFor(db, lead.id);
    if (await prime(db, cursor)) continue;

    const since = new Date(
      Math.max(cursor.seenThrough?.getTime() ?? 0, Date.now() - MAX_BACKFILL_MS),
    );

    const page = await adapter.fetchEvents(ctx, credentials as never, {
      stream,
      cursor: cursor.providerCursor,
      since,
      limit: 50,
      params: lead.params ?? {},
    });

    const wanted = new Set(group.filter((s) => s.enabled).map((s) => s.typeId));
    const fresh = page.events
      .filter((e) => wanted.has(e.type) && e.t.getTime() > since.getTime())
      .sort((a, b) => a.t.getTime() - b.t.getTime());

    for (const event of fresh) {
      const d = descriptor(row.provider, event.type);
      await emit(db, {
        userId: row.userId,
        integrationId: row.id,
        provider: row.provider,
        connectionLabel: row.accountLabel ?? row.label,
        typeId: event.type,
        severity: d?.severity ?? "info",
        title: event.title,
        body: event.body,
        amount: event.amount,
        currency: event.currency,
        // Host-checked here rather than trusting the adapter, because this is
        // the value the Mac will hand to `NSWorkspace`.
        url: safeUrl(event.url, row.provider),
        occurredAt: event.t,
        dedupeKey: `${row.id}:${event.type}:${event.id}`,
        localMinutes: minutes,
      });
    }

    await db
      .update(notificationCursor)
      .set({
        providerCursor: page.cursor,
        seenThrough: fresh.length > 0 ? fresh[fresh.length - 1]!.t : new Date(),
        lastEventId: fresh.length > 0 ? fresh[fresh.length - 1]!.id : cursor.lastEventId,
        evaluatedAt: new Date(),
      })
      .where(eq(notificationCursor.subscriptionId, lead.id));
  }
}

/**
 * The working-to-dead transition, raised with no provider call at all.
 *
 * Called from `recordFailure` and the token-refresh sweep, which already have
 * the *previous* status in hand — so this fires on the edge rather than on the
 * state. A revoked key fails on every poll, and notifying on the state would
 * mean one of these every five minutes until somebody reconnects.
 *
 * Unlike the Slack ping beside it, this is not gated on a webhook secret being
 * configured: it is the user's notification, not ours.
 */
export async function emitConnectionBroken(
  db: Database,
  previousStatus: string,
  row: { id: string; provider: string; label: string; accountLabel: string | null; userId: string },
): Promise<void> {
  if (previousStatus === "auth_failed") return;

  await emit(db, {
    userId: row.userId,
    integrationId: row.id,
    provider: row.provider,
    connectionLabel: row.accountLabel ?? row.label,
    typeId: "connection_broken",
    severity: "warning",
    title: `${row.label} needs reconnecting`,
    body: "The credentials were rejected. Reconnect to start the numbers again.",
    occurredAt: new Date(),
    // Deliberately not time-bucketed: one per connection per breakage, and the
    // next one only after somebody has reconnected and it broke again.
    dedupeKey: `${row.id}:connection_broken:${previousStatus}`,
    source: "internal",
    // No quiet hours, and no subscription row to check. This one is ours rather
    // than a provider's: it is the notification users would be angriest to have
    // missed, so it is not a preference.
  });
}

/** The cheap poll's answer: one primary-key read, no COUNT, no join. */
export async function readCursor(
  db: Database,
  userId: string,
): Promise<{ seq: number; unread: number; pollAfterSeconds: number }> {
  const [state] = await db
    .select()
    .from(notificationState)
    .where(eq(notificationState.userId, userId))
    .limit(1);

  if (!state || !state.enabled) {
    // Nothing enabled means stop asking. An hour, and the batch ride-along
    // still carries the truth if that changes.
    return { seq: state?.seq ?? 0, unread: 0, pollAfterSeconds: 3600 };
  }

  return {
    seq: state.seq,
    unread: state.unread,
    pollAfterSeconds: await pollAfterSeconds(db, userId),
  };
}

/**
 * How long the client should wait, as a floor on whatever its power state wants.
 *
 * The server decides because only the server knows the cron's stagger. Polling
 * faster than the evaluator runs produces literally nothing, so a user whose
 * subscriptions are all polled gets the cron's own period and no less.
 */
export async function pollAfterSeconds(db: Database, userId: string): Promise<number> {
  const [any] = await db
    .select({ id: notificationSubscription.id })
    .from(notificationSubscription)
    .where(
      and(eq(notificationSubscription.userId, userId), eq(notificationSubscription.enabled, true)),
    )
    .limit(1);

  return any ? 300 : 3600;
}

/**
 * One page of the feed.
 *
 * `since` walks forward from a cursor and `before` walks backward from one;
 * they are different questions and the caller has to pick. Both ride the
 * `(user_id, seq)` index.
 */
export async function feed(
  db: Database,
  userId: string,
  query: NotificationFeedQuery,
): Promise<NotificationFeed> {
  await ensureState(db, userId);
  const [state] = await db
    .select()
    .from(notificationState)
    .where(eq(notificationState.userId, userId))
    .limit(1);

  const limit = Math.min(query.limit, MAX_PAGE);
  const scope = [
    eq(notification.userId, userId),
    // `seq = 0` is the brief window inside `emit` between the insert and the
    // bump. Filtering it here is what makes that window invisible.
    gt(notification.seq, 0),
  ];
  if (query.integrationId) scope.push(eq(notification.integrationId, query.integrationId));
  if (query.since !== undefined) scope.push(gt(notification.seq, query.since));
  if (query.before !== undefined) scope.push(lt(notification.seq, query.before));

  // One more than asked for, so `hasMore` is an observation rather than a
  // second COUNT query.
  const rows = await db
    .select()
    .from(notification)
    .where(and(...scope))
    .orderBy(desc(notification.seq))
    .limit(limit + 1);

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;

  const connections = await connectionSummaries(db, userId);

  return {
    // The highest seq that *exists*, not the highest returned: advancing the
    // live cursor from a `before` page would mark unseen rows as seen.
    seq: state?.seq ?? 0,
    unread: state?.unread ?? 0,
    items: page
      .map((r) => ({
        id: r.id,
        seq: r.seq,
        integrationId: r.integrationId,
        provider: r.provider,
        connectionLabel: r.connectionLabel,
        typeId: r.typeId as NotificationTypeId,
        severity: r.severity as "info" | "success" | "warning",
        title: r.title,
        body: r.body,
        amount: r.amount,
        currency: r.currency,
        url: safeUrl(r.url, r.provider),
        occurredAt: r.occurredAt.toISOString(),
        createdAt: r.createdAt.toISOString(),
        read: r.readAt !== null,
        alert: r.alert,
      }))
      // Sorted on `occurredAt`, never on `seq`. A row found by a later
      // evaluation can carry a higher seq than an older one beside it, so
      // sorting on the cursor produces an apparently random order.
      .sort((x, y) => Date.parse(y.occurredAt) - Date.parse(x.occurredAt)),
    connections,
    hasMore,
    oldestSeq: page.length > 0 ? Math.min(...page.map((r) => r.seq)) : null,
    // Only ever set on a live-sync page: scrolling back through history is not
    // news, and must not suppress the banners for what arrives while you read.
    truncated: query.since !== undefined && (hasMore || page.length > TRUNCATE_AT),
    pollAfterSeconds: state?.enabled ? await pollAfterSeconds(db, userId) : 3600,
  };
}

/**
 * The sidebar.
 *
 * A separate query from the feed because a connection with nothing to report
 * still has to appear — which a page of rows cannot say. Driven off the
 * integration table rather than the notifications, so a brand-new connection
 * shows up before it has ever notified.
 */
async function connectionSummaries(db: Database, userId: string) {
  const integrations = await db
    .select({
      id: integrationTable.id,
      provider: integrationTable.provider,
      label: integrationTable.label,
      accountLabel: integrationTable.accountLabel,
    })
    .from(integrationTable)
    .where(eq(integrationTable.userId, userId));

  const counts = await db
    .select({
      integrationId: notification.integrationId,
      total: sql<number>`count(*)`,
      unread: sql<number>`sum(case when ${notification.readAt} is null then 1 else 0 end)`,
    })
    .from(notification)
    .where(and(eq(notification.userId, userId), gt(notification.seq, 0)))
    .groupBy(notification.integrationId);

  const byId = new Map(counts.map((c) => [c.integrationId, c]));

  const rows = integrations
    .filter((i) => descriptorsFor(i.provider).length > 0 || byId.has(i.id))
    .map((i) => ({
      integrationId: i.id,
      provider: i.provider,
      label: i.accountLabel ?? i.label,
      unread: Number(byId.get(i.id)?.unread ?? 0),
      total: Number(byId.get(i.id)?.total ?? 0),
    }));

  // Rows whose integration is gone still have notifications worth reading —
  // `integration_id` is SET NULL on disconnect precisely so they survive — so
  // they get one bucket rather than vanishing from the sidebar.
  const orphaned = byId.get(null);
  if (orphaned && Number(orphaned.total) > 0) {
    rows.push({
      integrationId: null as unknown as string,
      provider: "unknown",
      label: "Disconnected",
      unread: Number(orphaned.unread ?? 0),
      total: Number(orphaned.total),
    });
  }

  return rows;
}

export async function markRead(
  db: Database,
  userId: string,
  request: { upToSeq?: number; ids?: string[] },
): Promise<number> {
  const scope = [eq(notification.userId, userId), isNull(notification.readAt)];
  if (request.upToSeq !== undefined) scope.push(lte(notification.seq, request.upToSeq));
  if (request.ids !== undefined) {
    if (request.ids.length === 0) return currentUnread(db, userId);
    scope.push(inArray(notification.id, request.ids));
  }

  await db
    .update(notification)
    .set({ readAt: new Date() })
    .where(and(...scope));

  // Recomputed rather than decremented. The counter is denormalised for the
  // poll's sake, and a drifted unread badge is the bug users report; one COUNT
  // on an explicit user action is a fine price for it never drifting.
  return recomputeUnread(db, userId);
}

async function currentUnread(db: Database, userId: string): Promise<number> {
  const [state] = await db
    .select({ unread: notificationState.unread })
    .from(notificationState)
    .where(eq(notificationState.userId, userId))
    .limit(1);
  return state?.unread ?? 0;
}

async function recomputeUnread(db: Database, userId: string): Promise<number> {
  const [counted] = await db
    .select({ n: sql<number>`count(*)` })
    .from(notification)
    .where(
      and(eq(notification.userId, userId), isNull(notification.readAt), gt(notification.seq, 0)),
    );

  const unread = Number(counted?.n ?? 0);
  await db
    .update(notificationState)
    .set({ unread, updatedAt: new Date() })
    .where(eq(notificationState.userId, userId));
  return unread;
}

/**
 * Retention. Called from the cron beside `sweepCache`.
 *
 * Three rules, in order of how much the user would miss the row: triaged rows
 * go at 30 days, untriaged at 90, and anything past the per-user cap goes
 * whatever its age. Unbounded per-user growth is the alternative.
 */
export async function sweepNotifications(db: Database): Promise<void> {
  const now = Date.now();

  await db
    .delete(notification)
    .where(
      and(
        isNotNull(notification.readAt),
        lt(notification.createdAt, new Date(now - RETAIN_READ_MS)),
      ),
    );

  await db
    .delete(notification)
    .where(
      and(
        isNull(notification.readAt),
        lt(notification.createdAt, new Date(now - RETAIN_UNREAD_MS)),
      ),
    );

  // The cap, for the few users who would otherwise outrun the age rules. One
  // query to find them rather than a scan per user.
  const overflowing = await db
    .select({ userId: notification.userId, n: sql<number>`count(*)` })
    .from(notification)
    .groupBy(notification.userId)
    .having(sql`count(*) > ${MAX_PER_USER}`)
    .limit(50);

  for (const { userId } of overflowing) {
    const [boundary] = await db
      .select({ seq: notification.seq })
      .from(notification)
      .where(eq(notification.userId, userId))
      .orderBy(desc(notification.seq))
      .limit(1)
      .offset(MAX_PER_USER - 1);

    if (boundary) {
      await db
        .delete(notification)
        .where(and(eq(notification.userId, userId), lt(notification.seq, boundary.seq)));
      await recomputeUnread(db, userId);
    }
  }
}
