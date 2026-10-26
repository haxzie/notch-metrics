import {
  type AuthField,
  type Granularity,
  LocalConnectorManifest,
  LocalMetricDescriptor,
  type MetricFormat,
} from "./connector.ts";
import type { ConnectorContext, MetricRequest } from "./runtime.ts";
import { assertValid } from "./validate.ts";

/**
 * The authoring API: a metric is its description *and* the code that answers
 * it, in one object.
 *
 * What this replaces was two halves of one idea held apart. Every metric was
 * declared in `manifest.json` and answered inside a single `fetchMetric`
 * that opened with a chain of `if (request.metric === "...")`. Adding a
 * metric meant editing JSON, editing a branch, and keeping an id spelled the
 * same in both. Deleting one usually left the branch behind.
 *
 * ```js
 * export const downloads = createMetric({
 *   id: "downloads",
 *   label: "Downloads",
 *   unit: "count",
 *   series: { granularities: ["day"] },
 *   methodology: "Downloads reported by the registry for the window.",
 *   async fetch(ctx, request) {
 *     const response = await ctx.http(url(request));
 *     return { value: (await response.json()).total };
 *   },
 * });
 * ```
 *
 * ## What stays in the manifest, and why
 *
 * Not everything moved. `allowedHosts`, `auth` and `hostCredentials` are
 * **grants**: the hosts an app may reach, the secrets it asks you for, the
 * sign in it borrows. The app shows you those before it runs a line of the
 * connector's code, and enabling the app is what approves them. Reading them
 * out of the module would mean executing the module to find out what it
 * wants, which is the wrong order for a consent decision.
 *
 * Metric descriptors carry no such weight. They are labels, units and
 * shapes, so they belong next to the function that produces them.
 */

/** The window a metric is answered for, plus whatever the widget supplied. */
export type MetricFetch = (ctx: ConnectorContext, request: MetricRequest) => Promise<MetricAnswer>;

/** What a metric's `fetch` returns. The shape the tile is drawn from. */
export interface MetricAnswer {
  value: number;
  /** The previous equal-length window, for the delta. */
  previousValue?: number | null;
  /** One point per bucket, for a metric that draws a line or bars. */
  points?: { t: string; v: number }[];
  /** Rows, for a metric drawn as a split bar, ranked bars or a ring. */
  items?: {
    id: string;
    t: string;
    label: string;
    detail?: string | null;
    amount?: number | null;
    currency?: string | null;
    status?: string | null;
    state?: "succeeded" | "failed" | "running" | "neutral";
  }[];
  currency?: string | null;
  /** One line the tile shows under the figure. */
  note?: string;
  asOf?: string;
}

/**
 * The four kinds of answer, as four optional keys.
 *
 * Spelled this way instead of `shape: { kind: "series", ... }` because the
 * tagged union is a wire format and this is a thing a person types. One of
 * these is set; `createMetric` turns whichever it is into the `shape` the
 * manifest and the app already speak.
 */
interface Kinds {
  /** One number for the present. No window, so no range and no comparison. */
  scalar?: true;
  /** A number per bucket over the window. */
  series?: { granularities: Granularity[]; compare?: boolean };
  /** One number *for* the window, with a delta and no breakdown. */
  total?: { granularities: Granularity[]; compare?: boolean };
  /** Rows of categories. The same rows whatever the range says. */
  list?: { limit?: number } | true;
}

export interface MetricDefinition extends Kinds {
  id: string;
  label: string;
  /**
   * What fits in a notch tile. Twelve characters.
   *
   * Optional here and not in the wire descriptor: most labels are already
   * short enough to use as they are, and making every author write the same
   * word twice is how `shortLabel` ends up as a truncation of `label`, which
   * is the one thing it must not be.
   */
  shortLabel?: string;
  unit: LocalMetricDescriptor["unit"];
  currency?: string;
  format?: Partial<MetricFormat>;
  /** How this number is derived, in one sentence. Required. */
  methodology: string;
  /** Fields the *widget* supplies, rendered by the configure pane. */
  params?: AuthField[];
  freshnessSeconds?: number;
  linkTemplate?: string;
  /** Answers this metric for one window. */
  fetch: MetricFetch;
}

/** A metric, ready to be handed to `defineConnector`. */
export interface Metric {
  descriptor: LocalMetricDescriptor;
  fetch: MetricFetch;
}

function shapeOf(definition: Kinds, id: string): LocalMetricDescriptor["shape"] {
  if (definition.series) {
    return {
      kind: "series",
      granularities: definition.series.granularities as [Granularity, ...Granularity[]],
      compare: definition.series.compare ?? true,
    };
  }
  if (definition.total) {
    return {
      kind: "total",
      granularities: definition.total.granularities as [Granularity, ...Granularity[]],
      compare: definition.total.compare ?? true,
    };
  }
  if (definition.list) {
    return { kind: "list", limit: definition.list === true ? 10 : (definition.list.limit ?? 10) };
  }
  if (definition.scalar) return { kind: "scalar" };

  // Thrown at module load, so an author sees it the first time they run the
  // connector rather than as a tile that never fills.
  throw new Error(`Metric "${id}" declares no kind. Set one of scalar, series, total or list.`);
}

export function createMetric(definition: MetricDefinition): Metric {
  if (typeof definition.fetch !== "function") {
    throw new Error(`Metric "${definition.id}" has no fetch function.`);
  }

  // Validated here, at the smallest thing that can be wrong, so the message
  // names this metric. Left to `createApp`, the same mistake surfaced as
  // `metrics.3.params.0.type`, which is a position in an array rather than
  // something an author can look up in their own file.
  const descriptor = assertValid(
    LocalMetricDescriptor,
    {
      id: definition.id,
      label: definition.label,
      // Truncating would produce exactly the label-with-the-end-cut-off that
      // `shortLabel` exists to avoid, so a long label is the author's to fix
      // and the validator's to refuse.
      shortLabel: definition.shortLabel ?? definition.label,
      unit: definition.unit,
      ...(definition.currency ? { currency: definition.currency } : {}),
      ...(definition.format ? { format: definition.format } : {}),
      shape: shapeOf(definition, definition.id),
      methodology: definition.methodology,
      ...(definition.params ? { params: definition.params } : {}),
      ...(definition.freshnessSeconds ? { freshnessSeconds: definition.freshnessSeconds } : {}),
      ...(definition.linkTemplate ? { linkTemplate: definition.linkTemplate } : {}),
    },
    `Metric "${definition.id}"`,
  );

  return { descriptor, fetch: definition.fetch };
}

export interface AppDefinition {
  id: string;
  name: string;
  description: string;
  /** Shown in the Custom Apps list. Yours to display, never ours to compare. */
  version?: string;
  author?: string;
  appId?: string;
  icon?: LocalConnectorManifest["icon"];
  /**
   * Every host this app may contact. Nothing else is reachable.
   *
   * A **grant**, which is why it is here and not on a metric. The app shows
   * you this list before it runs a line of the connector's code, and
   * enabling the app is what approves it.
   */
  allowedHosts: string[];
  /** Fields the app asks you for. Omit for an app that needs nothing. */
  auth?: AuthField[];
  /** A sign in already on the Mac, which the app borrows. */
  hostCredentials?: LocalConnectorManifest["hostCredentials"];
  refreshIntervalSeconds?: number;
  timeoutMs?: number;
  /**
   * Proves the credential works and names the connection.
   *
   * Optional: an app against a public API has nothing to verify, and making
   * every one of those write an empty function was noise.
   */
  verify?: (ctx: ConnectorContext) => Promise<{
    accountLabel?: string | null;
    currency?: string | null;
    unavailableMetrics?: string[];
  }>;
  metrics: Metric[];
}

/** What a connector module default-exports. */
export interface App {
  /**
   * The manifest, derived from everything above.
   *
   * Emitted to `manifest.json` by `notch-metrics build`, which runs on the
   * author's machine. The file still exists on disk at install time, so the
   * Mac app reads an app's grants without executing any of its code. That
   * order matters: reading them out of the module would mean running the
   * module to find out what it wants, which is the wrong way round for a
   * consent decision.
   */
  manifest: LocalConnectorManifest;
  verify?: AppDefinition["verify"];
  /** Keyed by id, which is how the runner routes one request. */
  metrics: Record<string, Metric>;
  describe(): LocalMetricDescriptor[];
}

export function createApp(definition: AppDefinition): App {
  const metrics: Record<string, Metric> = {};

  for (const metric of definition.metrics) {
    const { id } = metric.descriptor;
    // Two metrics under one id means one of them silently never runs, and
    // which one depends on array order. Caught at load, named.
    if (metrics[id]) throw new Error(`Two metrics share the id "${id}".`);
    metrics[id] = metric;
  }

  const descriptors = Object.values(metrics).map((metric) => metric.descriptor);
  if (descriptors.length === 0) throw new Error("An app needs at least one metric.");

  const auth = definition.auth ?? [];
  const manifest = assertValid(
    LocalConnectorManifest,
    {
      schemaVersion: 1,
      id: definition.id,
      name: definition.name,
      description: definition.description,
      version: definition.version ?? "1.0.0",
      ...(definition.author ? { author: definition.author } : {}),
      ...(definition.appId ? { appId: definition.appId } : {}),
      ...(definition.icon ? { icon: definition.icon } : {}),
      // Derived, never asked for. Declaring `none` while listing fields is a
      // contradiction the author should not be able to write.
      authMode: auth.length > 0 ? "api_key" : "none",
      auth,
      hostCredentials: definition.hostCredentials ?? [],
      allowedHosts: definition.allowedHosts,
      metrics: descriptors,
      refreshIntervalSeconds: definition.refreshIntervalSeconds ?? 300,
      timeoutMs: definition.timeoutMs ?? 8_000,
      entry: "connector.mjs",
      createdAt: new Date(0).toISOString(),
      updatedAt: new Date(0).toISOString(),
    },
    `App "${definition.id}"`,
  );

  return {
    manifest,
    ...(definition.verify ? { verify: definition.verify } : {}),
    metrics,
    describe: () => descriptors,
  };
}
