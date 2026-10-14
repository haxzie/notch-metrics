import { z } from "zod";

/**
 * Identifiers that travel on the wire.
 *
 * These are `string` at runtime and branded at the type level, so a provider id
 * cannot be passed where an integration id is expected. The regexes are not
 * decoration: `PluginId` in particular becomes a *directory name* under the
 * user's Application Support folder, so anything containing `.`, `/` or `\`
 * has to be rejected before it reaches the filesystem.
 */

/**
 * A provider the Worker can call on the user's behalf.
 *
 * Every id here must have an adapter in `packages/integrations` — the registry
 * is typed as a total record so adding one to this list without writing the
 * adapter fails to compile, rather than throwing "unknown provider" at
 * whichever user connects it first.
 */
export const ProviderId = z.enum([
  // Revenue
  "stripe",
  "dodopayments",
  "lemonsqueezy",
  "polar",
  "paddle",
  "revenuecat",
  // Commerce
  "shopify",
  // Product analytics
  "posthog",
  "plausible",
  "mixpanel",
  "amplitude",
  "google-analytics",
  // Marketing and SEO
  "google-search-console",
  "youtube",
  // CRM
  "hubspot",
  "intercom",
  // Developer
  "github",
  // AI
  "openai",
  "anthropic",
]);
export type ProviderId = z.infer<typeof ProviderId>;

/**
 * How the catalogue is grouped, in the settings UI and on the website.
 *
 * Deliberately four buckets rather than a free-form tag: a user scanning for
 * "where do my signups come from" should find one short list, not eleven
 * categories of one.
 */
export const ConnectorCategory = z.enum([
  "revenue",
  "analytics",
  "marketing",
  "crm",
  "developer",
  "ai",
]);
export type ConnectorCategory = z.infer<typeof ConnectorCategory>;

export const CONNECTOR_CATEGORY_LABELS: Record<ConnectorCategory, string> = {
  revenue: "Revenue",
  analytics: "Product analytics",
  marketing: "Marketing & SEO",
  crm: "CRM",
  developer: "Developer",
  ai: "AI",
};

/**
 * The app a number came from, for display.
 *
 * A superset of `ProviderId`: every metric in the notch belongs to an app, and
 * that includes the ones the Worker does not fetch. A custom metric written by
 * an agent still reads "GitHub" rather than "Custom" when it says so.
 *
 * Deliberately a loose string rather than an enum. The app catalogue is
 * presentation, and an unrecognised id has a perfectly good fallback — whereas
 * a strict enum would make one unfamiliar value fail the decode of a whole
 * layout and blank every widget at once.
 */
export const AppId = z
  .string()
  .min(1)
  .max(40)
  .regex(/^[a-z0-9][a-z0-9-]*$/);
export type AppId = z.infer<typeof AppId>;

/**
 * Every metric any connector can produce.
 *
 * One shared vocabulary rather than per-connector ids, so a widget can say
 * "visitors" and the notch can render it the same whether it came from
 * Plausible or GA4 — and so swapping providers does not orphan a widget.
 * A connector declares which of these it supports in its manifest.
 */
export const MetricId = z.enum([
  // Revenue
  "mrr",
  "arr",
  "revenue",
  "one_time_sales",
  "refunds",
  "active_subscribers",
  "new_subscribers",
  "churned_subscribers",
  "trials",
  "recent_payments",
  // Commerce
  //
  // A store's book is orders, not a subscription ledger. `customers` and
  // `new_customers` are buyers, kept apart from the CRM's `contacts` below:
  // a contact is somebody being marketed to, and reading one as the other
  // next to a revenue tile is how a store overstates who has ever paid it.
  "orders",
  "average_order_value",
  "customers",
  "new_customers",
  // Product analytics
  "visitors",
  "pageviews",
  "sessions",
  "active_users",
  "new_users",
  "events",
  "bounce_rate",
  "conversion_rate",
  // Marketing and SEO
  "clicks",
  "impressions",
  "ctr",
  "average_position",
  // Audience and content
  //
  // `subscribers` is a channel's audience, not a billing book —
  // `active_subscribers` above is the one that costs money. Two ids rather
  // than one because a tile reading "Subscribers" next to a revenue figure
  // and a tile reading it next to watch time are different numbers, and
  // sharing the id would let a widget swap between them silently.
  "subscribers",
  "views",
  "watch_time",
  "average_view_duration",
  "likes",
  "comments",
  // Creator advertising economics. Not in the revenue block above, which is a
  // billing book: `revenue` there is what customers paid you, and these are
  // what an ad network paid you per thousand views. A widget swapping between
  // the two would be comparing a price list to a payout.
  "ad_revenue",
  "rpm",
  // Developer
  "stars",
  "forks",
  "open_issues",
  "open_pull_requests",
  "ci_runs",
  // AI
  "tokens",
  "input_tokens",
  "output_tokens",
  "api_requests",
  "api_spend",
  "followers",
  // CRM
  "contacts",
  "new_contacts",
  "open_deals",
  "won_deals",
  "pipeline_value",
  "open_conversations",
]);
export type MetricId = z.infer<typeof MetricId>;

/**
 * Every notification any connector can raise.
 *
 * One shared vocabulary rather than per-connector ids, for the same reason
 * `MetricId` is one: a Stripe payment and a Polar payment then render with one
 * row component and one copy string, and swapping providers does not orphan a
 * subscription the user already turned on.
 *
 * A connector declares which of these it raises in its manifest, so a new
 * provider's notifications ship with a Worker deploy and no Mac release.
 */
export const NotificationTypeId = z.enum([
  // Revenue. The whole reason anybody wants this.
  "payment_received",
  "payment_failed",
  "refund_issued",
  "subscription_started",
  "subscription_cancelled",
  "trial_ending",
  // Developer
  "issue_opened",
  "pull_request_opened",
  // Any scalar metric, against a bound only the user knows.
  "metric_threshold_crossed",
  // Ours, not a provider's: the working -> auth_failed edge. The highest-value
  // notification in the product and the only one that costs no provider call.
  "connection_broken",
]);
export type NotificationTypeId = z.infer<typeof NotificationTypeId>;

export const IntegrationId = z.string().min(1).max(64);
export type IntegrationId = z.infer<typeof IntegrationId>;

export const WidgetId = z.string().min(1).max(64);
export type WidgetId = z.infer<typeof WidgetId>;

/** A slug, because it is also a directory name. See the note above. */
export const PluginId = z.string().regex(/^[a-z0-9][a-z0-9-]{1,47}$/);
export type PluginId = z.infer<typeof PluginId>;
