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
  "stripe",
  "dodopayments",
  "lemonsqueezy",
  "polar",
  "google-analytics",
]);
export type ProviderId = z.infer<typeof ProviderId>;

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

export const MetricId = z.enum([
  "mrr",
  "revenue",
  "active_subscribers",
  "new_subscribers",
  "churned_subscribers",
  "refunds",
]);
export type MetricId = z.infer<typeof MetricId>;

export const IntegrationId = z.string().min(1).max(64);
export type IntegrationId = z.infer<typeof IntegrationId>;

export const WidgetId = z.string().min(1).max(64);
export type WidgetId = z.infer<typeof WidgetId>;

/** A slug, because it is also a directory name. See the note above. */
export const PluginId = z.string().regex(/^[a-z0-9][a-z0-9-]{1,47}$/);
export type PluginId = z.infer<typeof PluginId>;
