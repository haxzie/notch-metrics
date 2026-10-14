import { z } from "zod";
import { Granularity } from "./money.ts";
import { ConnectorCategory, MetricId, NotificationTypeId, ProviderId } from "./ids.ts";
import { MetricUnit } from "./metric.ts";
import { NotificationComparator, NotificationKind, NotificationSeverity } from "./notification.ts";

/**
 * A credentials field, rendered dynamically by the Mac settings UI.
 *
 * `type` is an enum including `secret` rather than a `masked: true` flag. That
 * is deliberate: an app that meets an unknown *type* can fall back to `string`
 * and still render a usable form, whereas an app that meets an unknown *flag*
 * silently renders a secret in plain text.
 */
export const AuthField = z.object({
  key: z.string().regex(/^[a-z][a-z0-9_]*$/),
  label: z.string(),
  type: z.enum(["string", "secret", "select", "url", "boolean"]),
  required: z.boolean().default(true),
  placeholder: z.string().optional(),
  /** One line, rendered under the field. Where to find the key, which scopes. */
  help: z.string().optional(),
  /** JS-flavour regex for client-side prevalidation. The server revalidates. */
  pattern: z.string().optional(),
  options: z.array(z.object({ value: z.string(), label: z.string() })).optional(),
  default: z.string().optional(),
});
export type AuthField = z.infer<typeof AuthField>;

export const MetricDescriptor = z.object({
  id: MetricId,
  label: z.string(),
  /** What fits in a notch tile. Twelve characters, not a truncation of `label`. */
  shortLabel: z.string().max(12),
  unit: MetricUnit,
  granularities: z.array(Granularity).nonempty(),
  /** False means a number with no sparkline — MRR at `month` granularity, say. */
  supportsSeries: z.boolean(),
  supportsCompare: z.boolean(),
  /**
   * Extra words that should find this metric in search.
   *
   * Nobody types "active_subscribers" — they type "customers", or "churn",
   * or "how many people pay me". Defaulted rather than required so a new
   * metric is searchable by its label on day one and gets synonyms later.
   */
  keywords: z.array(z.string()).optional(),
  help: z.string().optional(),
  /**
   * Fields the *widget* supplies, rendered in the configure pane.
   *
   * Declared per metric rather than per connector because they differ within
   * one: GitHub's stars need a repository and its followers do not. Same
   * `AuthField` shape as the connect form, so an app that already renders one
   * renders these with no new code.
   *
   * Optional on the wire — a metric that takes none omits it, and an older
   * app that has never heard of it ignores the field rather than failing to
   * decode the whole catalogue.
   */
  params: z.array(AuthField).optional(),
  /**
   * How this number is derived, in one sentence, shown in a tooltip.
   *
   * Required, not optional. "MRR" is always somebody's definition — gross or
   * net, discounts applied or not, trials counted or not — and it is the one
   * number users will argue about. Saying which one we mean costs a sentence.
   */
  methodology: z.string(),
  /**
   * How long a computed figure stays fresh, when the granularity's own
   * answer is wrong for this metric.
   *
   * The cache is keyed by bucket — a daily bucket holds for fifteen minutes,
   * because there is no reason to re-walk Stripe's subscription list that
   * often for a monthly figure. A CI feed is the opposite: the bucket says
   * nothing about it, and fifteen minutes is long enough for a tile to
   * report a build that has since gone red.
   *
   * Server-side only. The floor is what stops a widget from turning the
   * notch's five-minute poll into a provider request every time.
   */
  freshnessSeconds: z.number().int().min(60).max(86_400).optional(),
});
export type MetricDescriptor = z.infer<typeof MetricDescriptor>;

/**
 * Where the evaluator gets its input.
 *
 * A discriminated union rather than a flag, because each arm is a different
 * amount of work and a different honesty claim — and because an app meeting an
 * unknown `from` can grey the toggle out instead of rendering a switch that
 * silently never fires. Same argument as `AuthField.type` over `masked: true`.
 *
 * `metric_items` and `metric_value` cost nothing: the cron already warms those
 * series, so the evaluator reads a number it was going to fetch anyway.
 * `adapter_events` needs the provider to implement `fetchEvents`.
 */
export const NotificationSource = z.discriminatedUnion("from", [
  /** Rows of a list metric. `MetricListItem.id` is provider-stable, which is
   *  what makes it a real dedupe key rather than a guess. */
  z.object({ from: z.literal("metric_items"), metric: MetricId }),
  /** The scalar `MetricSeries.value`, against a bound the user supplies. */
  z.object({ from: z.literal("metric_value"), metric: MetricId }),
  /** One `fetchEvents` stream. Several descriptors usually share one stream —
   *  one poll, three notification types. */
  z.object({ from: z.literal("adapter_events"), stream: z.string() }),
  /** Raised by the Worker itself, with no provider call at all. */
  z.object({ from: z.literal("internal") }),
]);
export type NotificationSource = z.infer<typeof NotificationSource>;

export const NotificationThresholdSpec = z.object({
  metric: MetricId,
  comparators: z.array(NotificationComparator).nonempty(),
  unit: MetricUnit,
  /** Pre-filled in the editor, so the user edits a number rather than invents
   *  one. Minor units when the metric is currency, percent for a `pct_` one. */
  suggestedValue: z.number().nullable(),
});
export type NotificationThresholdSpec = z.infer<typeof NotificationThresholdSpec>;

/**
 * A notification a connector can raise, declared rather than coded.
 *
 * The same contract `MetricDescriptor` is: every field drives something the
 * user sees, the Mac renders the toggle list and the severity from these fields
 * and hardcodes no provider, and a new provider's notifications therefore ship
 * with a Worker deploy and no app release. Getting one wrong produces a toggle
 * that lies rather than a build that fails.
 */
export const NotificationDescriptor = z.object({
  id: NotificationTypeId,
  kind: NotificationKind,
  label: z.string(),
  /** The notification row's leading line. Not a truncation of `label`. */
  shortLabel: z.string().max(24),
  severity: NotificationSeverity,
  /**
   * What exactly makes this fire, in one sentence, rendered under the toggle.
   *
   * Required, not optional — same argument as `MetricDescriptor.methodology`.
   * "A failed payment" is somebody's definition: first attempt or final retry,
   * and whether a $0 invoice counts.
   */
  methodology: z.string(),
  source: NotificationSource,
  /** `kind: "threshold"` only. */
  threshold: NotificationThresholdSpec.optional(),
  /**
   * Fields the *subscription* supplies. Same `AuthField` shape as
   * `MetricDescriptor.params`, so an app that renders one renders these with
   * no new code — and unlike a widget-scoped metric, a subscription carrying
   * its own params *can* be warmed from the cron.
   */
  params: z.array(AuthField).optional(),
  /**
   * Whether connecting the provider switches this on.
   *
   * Decided per descriptor rather than globally, because both global answers
   * are wrong: opt-out means a Stripe account taking 400 charges a day gets a
   * notch that will not shut up on day one, and opt-in means nobody ever finds
   * the feature. "Connection broken" ships on; "new payment" ships off.
   */
  defaultEnabled: z.boolean().default(false),
  /**
   * False for the things the product must always be able to say — a revoked
   * key is not a preference. The Mac renders a locked row rather than hiding
   * it, so the user can still see what they will be told.
   */
  userConfigurable: z.boolean().default(true),
  /**
   * Re-arm floor, honoured by the evaluator and seeded onto the subscription.
   *
   * A number resting on a threshold must not fire every tick, and a user
   * cannot be expected to think of that.
   */
  minIntervalSeconds: z.number().int().min(60).default(3600),
  /** Above this in one evaluation the batch collapses to "7 new payments",
   *  rather than seven rows nobody reads. */
  maxBurst: z.number().int().min(1).default(5),
});
export type NotificationDescriptor = z.infer<typeof NotificationDescriptor>;

/**
 * What the connect page needs to know about an OAuth connector before the
 * user has authorised anything.
 */
export const OAuthDescriptor = z.object({
  /** Shown on the connect page so the user knows what they are granting. */
  scopeSummary: z.array(z.string()),
  /**
   * Whether the user has to choose something after authorising — a GA4
   * property, a Search Console site, an Ads customer. The link flow pauses on
   * `awaiting_configuration` when this is set.
   */
  requiresSelection: z.boolean().default(false),
  /** What they are choosing, for the picker's heading. */
  selectionLabel: z.string().optional(),
});
export type OAuthDescriptor = z.infer<typeof OAuthDescriptor>;

export const ProviderManifest = z.object({
  id: ProviderId,
  name: z.string(),
  category: ConnectorCategory,
  tagline: z.string(),
  /** Where to find the API key, linked from the connect sheet. */
  docsUrl: z.url(),
  /**
   * The connector's mark, resolved against the *website* — not the assets
   * host, which only mirrors releases and 404s these.
   *
   * Served rather than bundled so a new provider's logo ships with the
   * manifest rather than with the app. Both clients currently resolve the
   * mark from the connector id instead, so this is belt and braces for one
   * that cannot; `registry.test.ts` pins it to the path that actually
   * serves, because a field nothing reads is a field nothing notices has
   * gone stale.
   */
  iconPath: z.string(),
  accentColor: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  /** What someone might call this app other than its name — "payments",
   *  "billing", "analytics". Searched alongside the name. */
  keywords: z.array(z.string()).optional(),
  authMode: z.enum(["api_key", "oauth2"]),
  /** Present only when `authMode` is `oauth2`. */
  oauth: OAuthDescriptor.optional(),
  /**
   * What the connect page asks for.
   *
   * For an OAuth connector this is usually empty — tokens are never typed in
   * by a human — but some need something alongside, like Plausible's site id.
   */
  fields: z.array(AuthField),
  metrics: z.array(MetricDescriptor).nonempty(),
  /**
   * What this connector can notify about.
   *
   * Optional rather than defaulted, which is the same choice `keywords`,
   * `MetricDescriptor.params` and `MetricSeries.items` already make: a
   * provider that notifies about nothing omits the key, and an older app that
   * has never heard of it ignores the field rather than failing to decode the
   * whole catalogue. A default would also force all nineteen existing manifest
   * literals to carry an empty array, since `z.infer` makes a defaulted field
   * required on the *output* type.
   *
   * Adding this field rehashes `REGISTRY_VERSION`, which is the catalogue ETag,
   * so every client refetches the catalogue once on deploy — the mechanism
   * working rather than a bug.
   */
  notifications: z.array(NotificationDescriptor).optional(),
  /** The outbound allowlist enforced by `AdapterContext.http`. */
  allowedHosts: z.array(z.string()).nonempty(),
  status: z.enum(["stable", "beta", "coming_soon"]),
  /**
   * The oldest Mac build that can render this manifest.
   *
   * Serving manifests is what lets a provider ship with no app release — but a
   * provider needing a field type the installed app has never heard of cannot
   * be rendered, and a half-rendered credentials form submits a credential set
   * the adapter will reject. The app filters on this and offers an update
   * instead of a broken form.
   */
  minAppVersion: z.string(),
});
export type ProviderManifest = z.infer<typeof ProviderManifest>;

export const ProviderManifestList = z.object({
  /** Bumped whenever any manifest changes; also the ETag. */
  version: z.string(),
  providers: z.array(ProviderManifest),
});
export type ProviderManifestList = z.infer<typeof ProviderManifestList>;
