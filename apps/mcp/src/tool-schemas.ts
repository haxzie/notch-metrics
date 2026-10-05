import { z } from "zod";

/**
 * Tool input shapes, written in zod 3.
 *
 * The MCP SDK converts these to JSON Schema and is pinned to zod 3, while
 * `@notch/schemas` is zod 4 — the two are structurally different types and
 * passing one where the other is expected does not compile. So the wire shape
 * is declared here for the SDK, and the *authoritative* validation still
 * happens inside each handler with `PluginManifest.parse`. The duplication is
 * small, deliberate, and guarded by a test that round-trips one through the
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
