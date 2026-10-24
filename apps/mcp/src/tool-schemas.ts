import { z } from "zod";

/**
 * Tool input shapes, declared separately from `@notch/schemas`.
 *
 * Not a zod-version split any more. The whole workspace is on zod 4 — the SDK
 * accepts `^3.25 || ^4.0`, and the version skew this file used to describe is
 * what made the published bundle fail on its first run: inlined zod-4 schemas
 * resolving `zod` to the server's own zod 3, where `z.url()` does not exist.
 *
 * They stay separate because they answer different questions. This is the
 * shape the SDK advertises to an agent: tolerant, with every field the agent
 * may supply and none of the ones we fill in. The *authoritative* validation
 * still happens inside each handler with `PluginManifest.parse`, which
 * applies the defaults and rejects what this deliberately lets through. The
 * duplication is small and guarded by a test that round-trips one through the
 * other.
 */
export const granularity = z.enum(["hour", "day", "week", "month"]);

export const manifestInput = z.object({
  id: z
    .string()
    .regex(/^[a-z0-9][a-z0-9-]{1,47}$/)
    .describe("Lowercase slug. Becomes the directory name."),
  name: z.string().min(1).max(60),
  shortLabel: z.string().max(12).describe("What fits in a notch tile."),
  description: z.string().max(400),
  unit: z.enum(["currency", "count", "ratio", "duration", "bytes"]),
  currency: z.string().length(3).optional().describe("ISO 4217. Required when unit is currency."),
  format: z
    .object({
      decimals: z.number().int().min(0).max(4).optional(),
      compact: z.boolean().optional(),
      prefix: z.string().max(3).optional(),
      suffix: z.string().max(4).optional(),
    })
    .optional(),
  granularities: z.array(granularity).min(1).optional(),
  supportsSeries: z.boolean().optional(),
  refreshIntervalSeconds: z.number().int().min(60).max(86_400).optional(),
  secrets: z
    .array(
      z.object({
        key: z.string().regex(/^[A-Z][A-Z0-9_]*$/),
        label: z.string(),
        help: z.string().optional(),
        required: z.boolean().optional(),
      }),
    )
    .optional()
    .describe("Names only. Values go in the Keychain via set_metric_secret."),
  allowedHosts: z
    .array(z.string())
    .min(1)
    .describe("Exact hostnames, or one leading `*.`. No bare `*`."),
  timeoutMs: z.number().int().min(1_000).max(20_000).optional(),
  author: z.string().optional(),
  minAppVersion: z.string().optional(),
});

export type ManifestInput = z.infer<typeof manifestInput>;
