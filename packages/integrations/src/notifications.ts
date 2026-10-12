import type { MetricId, MetricUnit, NotificationDescriptor } from "@notch/schemas";

/**
 * Notification descriptors shared across providers.
 *
 * One definition rather than six copies, for the same reason
 * `recentPaymentsDescriptor` exists: the label, the severity and the burst cap
 * have to agree across providers, or the same notification arrives under two
 * names depending on who you take payments with. Only the methodology is the
 * provider's own, because what counts as a payment is.
 */

/**
 * "New payment", driven off the `recent_payments` list metric.
 *
 * The honest event source that costs no adapter work: `MetricListItem.id` is
 * the provider's own charge id, so it is a real dedupe key rather than a guess
 * derived from a timestamp.
 */
export function paymentReceivedNotification(methodology: string): NotificationDescriptor {
  return {
    id: "payment_received",
    kind: "event",
    label: "New payment",
    shortLabel: "New payment",
    severity: "success",
    methodology,
    source: { from: "metric_items", metric: "recent_payments" },
    // Off by default. A store taking four hundred charges a day would otherwise
    // get a notch that will not shut up on the day they connect it.
    defaultEnabled: false,
    userConfigurable: true,
    // The list is only re-read on the cron's own cadence, so a shorter floor
    // than this would never be reached anyway.
    minIntervalSeconds: 60,
    // Above five in one evaluation this collapses to "7 new payments". Seven
    // separate rows is seven things nobody reads.
    maxBurst: 5,
  };
}

/**
 * "This number crossed a line I chose."
 *
 * Always ships disabled, and `seedSubscriptions` enforces that independently:
 * a threshold needs a bound only the user knows, so a default would fire on day
 * one and be wrong.
 */
export function metricThresholdNotification(options: {
  metric: MetricId;
  unit: MetricUnit;
  label: string;
  methodology: string;
  /** Pre-filled in the editor so the user edits a number rather than invents
   *  one. Minor units when the metric is currency. */
  suggestedValue: number | null;
}): NotificationDescriptor {
  return {
    id: "metric_threshold_crossed",
    kind: "threshold",
    label: options.label,
    shortLabel: "Threshold",
    severity: "info",
    methodology: options.methodology,
    source: { from: "metric_value", metric: options.metric },
    threshold: {
      metric: options.metric,
      comparators: ["above", "below", "pct_change_down", "pct_change_up"],
      unit: options.unit,
      suggestedValue: options.suggestedValue,
    },
    defaultEnabled: false,
    userConfigurable: true,
    minIntervalSeconds: 3600,
    maxBurst: 1,
  };
}
