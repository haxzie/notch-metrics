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

export const ProviderId = z.enum(["stripe", "dodopayments", "lemonsqueezy", "polar"]);
export type ProviderId = z.infer<typeof ProviderId>;

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
