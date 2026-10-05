import { z } from "zod";
import { Granularity } from "./money.ts";
import { MetricId, ProviderId } from "./ids.ts";
import { MetricUnit } from "./metric.ts";

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
  help: z.string().optional(),
  /**
   * How this number is derived, in one sentence, shown in a tooltip.
   *
   * Required, not optional. "MRR" is always somebody's definition — gross or
   * net, discounts applied or not, trials counted or not — and it is the one
   * number users will argue about. Saying which one we mean costs a sentence.
   */
  methodology: z.string(),
});
export type MetricDescriptor = z.infer<typeof MetricDescriptor>;

export const ProviderManifest = z.object({
  id: ProviderId,
  name: z.string(),
  tagline: z.string(),
  /** Where to find the API key, linked from the connect sheet. */
  docsUrl: z.url(),
  /** Resolved against the assets host, so a new provider's logo ships with the
   *  manifest rather than with the app. */
  iconPath: z.string(),
  accentColor: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  authMode: z.enum(["api_key", "oauth2"]),
  fields: z.array(AuthField),
  metrics: z.array(MetricDescriptor).nonempty(),
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
