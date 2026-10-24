import { z } from "zod";

/**
 * The tool inputs for connector authoring.
 *
 * Declared separately from `@notchmetrics/core` for the same reason
 * `tool-schemas.ts` is: this is the tolerant shape the SDK advertises to an
 * agent, not the one that decides what is valid. The authoritative shape is
 * still
 * `LocalConnectorManifest` — everything here is re-parsed with it before
 * anything is written, so this is a tolerant front door and not a second
 * definition of the truth.
 */

/** Mirrors `AuthField`. Lower-case keys, matching the built-in connect forms. */
const authField = z.object({
  key: z.string().regex(/^[a-z][a-z0-9_]*$/, "lower-case letters, digits and underscores"),
  label: z.string(),
  type: z.enum(["string", "secret", "select", "url", "boolean"]),
  required: z.boolean().optional(),
  placeholder: z.string().optional(),
  help: z.string().optional(),
  pattern: z.string().optional(),
  options: z.array(z.object({ value: z.string(), label: z.string() })).optional(),
  default: z.string().optional(),
});

const granularity = z.enum(["hour", "day", "week", "month"]);

/**
 * The four shapes, flattened for an agent.
 *
 * `kind` decides which controls the tile offers and what `fetchMetric` must
 * return — so getting it wrong produces a widget that lies rather than a
 * build that fails, which is why `describe_connector_runtime` spends most of
 * its words here.
 */
const metricShape = z.union([
  z.object({ kind: z.literal("scalar") }),
  z.object({
    kind: z.literal("series"),
    granularities: z.array(granularity).min(1),
    compare: z.boolean().optional(),
  }),
  z.object({
    kind: z.literal("total"),
    granularities: z.array(granularity).min(1),
    compare: z.boolean().optional(),
  }),
  z.object({ kind: z.literal("list"), limit: z.number().int().min(1).max(50).optional() }),
]);

const metricDescriptor = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*$/),
  label: z.string().min(1).max(60),
  shortLabel: z.string().max(12),
  unit: z.enum(["currency", "count", "ratio", "duration", "bytes"]),
  currency: z.string().length(3).optional(),
  shape: metricShape,
  methodology: z.string().min(1),
  params: z.array(authField).optional(),
  freshnessSeconds: z.number().int().min(60).max(86_400).optional(),
  linkTemplate: z.string().url().optional(),
});

export const connectorManifestInput = z.object({
  id: z.string().regex(/^[a-z0-9][a-z0-9-]{1,47}$/),
  name: z.string().min(1).max(60),
  description: z.string().max(400),
  appId: z.string().optional(),
  author: z.string().optional(),
  auth: z.array(authField).optional(),
  allowedHosts: z.array(z.string()).min(1),
  metrics: z.array(metricDescriptor).min(1),
  refreshIntervalSeconds: z.number().int().min(60).max(86_400).optional(),
  timeoutMs: z.number().int().min(1_000).max(20_000).optional(),
});
export type ConnectorManifestInput = z.infer<typeof connectorManifestInput>;

/** Fills the fields the authoritative schema defaults, so it can parse. */
export function fillConnector(input: ConnectorManifestInput): Record<string, unknown> {
  const now = new Date().toISOString();
  return {
    ...input,
    schemaVersion: 1,
    entry: "connector.mjs",
    createdAt: now,
    updatedAt: now,
  };
}
