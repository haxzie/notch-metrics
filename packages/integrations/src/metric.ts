import { Granularity } from "@notch/schemas";
import type {
  AuthField,
  MetricDescriptor,
  MetricFormat,
  MetricId,
  ProviderManifest,
} from "@notch/schemas";
import type {
  AdapterContext,
  EventPage,
  EventRequest,
  MetricRequest,
  ProviderAdapter,
  RawListItem,
  RawSeries,
  VerifyResult,
} from "./types.ts";
import { ProviderError } from "./types.ts";
import type { OAuthConfig } from "./oauth.ts";
import type { ZodType } from "zod";

/**
 * What a metric *is*, as three arms rather than two booleans.
 *
 * `supportsSeries` and `supportsCompare` encode this today, and the encoding
 * loses the distinction that matters: `stars` and `ci_runs` are both
 * `false, false` for unrelated reasons — one has no history to show, the
 * other is a feed with no window at all. Nothing in the pair says which.
 *
 * Shape is also what decides the *return* type, which is why the factories
 * below are per shape: declaring `series` and forgetting `points` is then a
 * compile error rather than a tile that renders a flat line.
 *
 * Server-side only, for now. The wire still carries the legacy booleans —
 * see `toDescriptor`.
 */
export type MetricShape =
  /** One number for the present. No window, so no range and no comparison. */
  | { kind: "scalar" }
  /**
   * A number per bucket over a window.
   *
   * `granularities` lives here and nowhere else. On a scalar it was
   * decoration — `stars` has declared `["day", "week", "month"]` since the
   * connector shipped and nothing has ever read it — and decoration that
   * looks load-bearing is how both LLM connectors came to promise `12m`.
   */
  | { kind: "series"; granularities: [Granularity, ...Granularity[]]; compare: boolean }
  /**
   * One number for a window, with a delta, and no breakdown behind it.
   *
   * Not a shape I expected until converting found two of them. RevenueCat's
   * revenue comes from a Charts endpoint that answers one figure per call, so
   * a thirty-point sparkline would be a minute of its rate budget per widget;
   * YouTube's subscriber count is the same story. Both want a Range control
   * and a comparison and cannot draw a chart.
   *
   * This is the `supportsSeries: false, supportsCompare: true` pair, which I
   * had assumed was nonsense. `granularities` is load-bearing here for the
   * same reason it is on a series: it decides which ranges the pane offers.
   */
  | { kind: "total"; granularities: [Granularity, ...Granularity[]]; compare: boolean }
  /**
   * Rows of what just happened. The same rows whatever the range says.
   *
   * `limit` was `CI_RUNS_LIMIT` in one file and `RECENT_PAYMENTS_LIMIT` in
   * another, both ten, both with the same comment about the tallest tile.
   */
  | { kind: "list"; limit: number };

/** Fields every shape declares, and which all end up on the wire descriptor. */
interface CommonMetric {
  id: MetricId;
  label: string;
  /** Twelve characters. Not a truncation of `label`. */
  shortLabel: string;
  /**
   * Narrower than `MetricUnit`, which also has `bytes`: nothing fetched over
   * HTTP from a SaaS API is a size. The wrappers below echo this onto the
   * result, so a `fetch` returns a number and not a unit it already declared.
   */
  unit: RawSeries["unit"];
  methodology: string;
  keywords?: string[];
  help?: string;
  params?: AuthField[];
  freshnessSeconds?: number;
  linkTemplate?: string;
}

/** Everything a `fetch` may add alongside the figure. */
interface ResultExtras {
  /** Required when `unit` is `currency`; null when the account mixes them. */
  currency?: string | null;
  note?: string;
  asOf?: Date;
  format?: Partial<MetricFormat>;
}

export interface ScalarResult extends ResultExtras {
  value: number;
  /**
   * The instant the reading is for, when it is not now.
   *
   * Stripe's MRR and active-subscriber counts are snapshots of the book at
   * the end of the window rather than readings taken at this moment, and
   * both timestamped their one point `request.to`. Same field, same reason,
   * as on `TotalResult`.
   */
  at?: Date;
}

export interface TotalResult extends ResultExtras {
  value: number;
  previousValue?: number | null;
  /**
   * The instant the figure is for, when it is not now.
   *
   * RevenueCat's revenue is a total to the end of the window, not a reading
   * taken at this moment, and it timestamped its one point `request.to`.
   */
  at?: Date;
}

export interface SeriesResult extends ResultExtras {
  points: { t: Date; v: number }[];
  value: number;
  previousValue?: number | null;
}

export interface ListResult extends ResultExtras {
  items: RawListItem[];
  /** As on `ScalarResult`. A feed's one point is otherwise stamped now. */
  at?: Date;
  /** Defaults to `items.length`, which is what every list metric sets by hand. */
  value?: number;
}

type Fetch<C, R> = (ctx: AdapterContext, credentials: C, request: MetricRequest) => Promise<R>;

/**
 * One metric: its descriptor and the code that answers it, in one object.
 *
 * The two were a manifest entry and a `case` five hundred lines apart, with a
 * third hand-written list of ids in `verify`. Nothing connected them, which
 * is why a `granularities` promising a bucket the `case` throws on was
 * invisible until it reached a tile.
 */
export type MetricDefinition<C extends Record<string, unknown> = Record<string, unknown>> =
  CommonMetric &
    (
      | { shape: { kind: "scalar" }; fetch: Fetch<C, ScalarResult> }
      | {
          shape: {
            kind: "series";
            granularities: [Granularity, ...Granularity[]];
            compare: boolean;
          };
          fetch: Fetch<C, SeriesResult>;
        }
      | {
          shape: {
            kind: "total";
            granularities: [Granularity, ...Granularity[]];
            compare: boolean;
          };
          fetch: Fetch<C, TotalResult>;
        }
      | { shape: { kind: "list"; limit: number }; fetch: Fetch<C, ListResult> }
    );

/** The author-facing options, with the shape flattened to the top level. */
type ScalarOptions<C> = CommonMetric & { fetch: Fetch<C, ScalarResult> };
type SeriesOptions<C> = CommonMetric & {
  granularities: [Granularity, ...Granularity[]];
  /** The previous equal-length window, for the delta arrow. */
  compare: boolean;
  fetch: Fetch<C, SeriesResult>;
};
type TotalOptions<C> = CommonMetric & {
  granularities: [Granularity, ...Granularity[]];
  compare: boolean;
  fetch: Fetch<C, TotalResult>;
};
type ListOptions<C> = CommonMetric & {
  limit: number;
  fetch: Fetch<C, ListResult>;
};

/**
 * Three factories rather than one `metric({ shape })`.
 *
 * A single entry point has the same inference problem as a bare annotated
 * literal: TypeScript has to resolve the arm from a field *inside* the
 * object, so a mistake in `fetch` surfaces as "no overload matches this
 * call" against line one of a forty-line literal. With the discriminant in
 * the function name, inference runs forwards and the error lands on the field
 * that is actually wrong.
 *
 * Identity functions at runtime. No per-call validation: a bad descriptor can
 * only be written at author time, and `registry.test.ts` already parses every
 * manifest — paying for that check on every catalogue serve would be a cost
 * on users for a mistake only we can make.
 */
export function scalarMetric<C extends Record<string, unknown>>(
  options: ScalarOptions<C>,
): MetricDefinition<C> {
  return { ...options, shape: { kind: "scalar" } };
}

export function seriesMetric<C extends Record<string, unknown>>(
  options: SeriesOptions<C>,
): MetricDefinition<C> {
  const { granularities, compare, ...rest } = options;
  return { ...rest, shape: { kind: "series", granularities, compare } };
}

export function totalMetric<C extends Record<string, unknown>>(
  options: TotalOptions<C>,
): MetricDefinition<C> {
  const { granularities, compare, ...rest } = options;
  return { ...rest, shape: { kind: "total", granularities, compare } };
}

export function listMetric<C extends Record<string, unknown>>(
  options: ListOptions<C>,
): MetricDefinition<C> {
  const { limit, ...rest } = options;
  return { ...rest, shape: { kind: "list", limit } };
}

/**
 * The three factories bound to one provider's credential type.
 *
 * Without this every metric file repeats `<GitHubCredentials>`, and a file
 * that forgets it silently widens `creds` to the base record — which still
 * compiles and then fails on the first property read. Same trick as
 * `googleOAuth<C>`.
 */
export function metricsFor<C extends Record<string, unknown>>(): {
  scalar: (options: ScalarOptions<C>) => MetricDefinition<C>;
  series: (options: SeriesOptions<C>) => MetricDefinition<C>;
  total: (options: TotalOptions<C>) => MetricDefinition<C>;
  list: (options: ListOptions<C>) => MetricDefinition<C>;
} {
  return {
    scalar: scalarMetric<C>,
    series: seriesMetric<C>,
    total: totalMetric<C>,
    list: listMetric<C>,
  };
}

/**
 * The wire descriptor for a definition.
 *
 * `shape` deliberately does **not** cross the wire yet. Adding a field to
 * `MetricDescriptor` means regenerating `contracts/`, hand-editing the Swift
 * structs and shipping an app that reads it — so this converts to the three
 * legacy fields instead, and installed apps keep deriving their controls from
 * the booleans with no idea anything changed. Putting `shape` on the wire is
 * its own change, with its own contract regeneration.
 *
 * Off the series arm `granularities` is emitted as every bucket, which looks
 * backwards and is not. The schema requires a non-empty array and nothing
 * interprets it as a bucketing claim once `supportsSeries` is false — but
 * installed apps run `clampRange()` unconditionally, not only when the Range
 * row is shown. A narrow list there would silently rewrite the stored range
 * of a snapshot widget the first time its configure pane opened: invisible,
 * since the range is unread for a snapshot, and a layout write and a
 * revision bump for nothing. Permissive is what makes that a no-op.
 *
 * Gating `clampRange` on `usesTimeWindow` is the real fix and is an app
 * change; this has to hold for the builds already out there.
 */
export function toDescriptor(definition: MetricDefinition<never>): MetricDescriptor {
  const { shape, fetch: _fetch, ...common } = definition;
  return {
    ...common,
    // A series and a total both declare theirs; a scalar and a list have no
    // window, so they get every bucket — see the note above on `clampRange`.
    granularities:
      shape.kind === "series" || shape.kind === "total"
        ? shape.granularities
        : [...Granularity.options],
    supportsSeries: shape.kind === "series",
    supportsCompare: (shape.kind === "series" || shape.kind === "total") && shape.compare,
  };
}

/**
 * Turns a definition's result into the `RawSeries` the server stores.
 *
 * This is where the "one point, at now" rule stops being a convention every
 * author has to remember and becomes the only thing the types allow. A
 * snapshot used to hand-write `points: [{ t: ctx.now(), v: value }]`, and a
 * provider that instead spread a single reading across a window would have
 * produced a flat line that looks like history.
 */
function toRawSeries(
  definition: MetricDefinition<never>,
  ctx: AdapterContext,
  result: ScalarResult | SeriesResult | TotalResult | ListResult,
): RawSeries {
  // One reading of the clock, not three. `ctx.now()` is `() => new Date()`,
  // so a snapshot that timestamped its point and its `asOf` separately could
  // put them milliseconds apart — which the old hand-written `snapshot()`
  // helpers all did, harmlessly and for no reason.
  const at = ctx.now();

  const extras = {
    ...(result.note !== undefined ? { note: result.note } : {}),
    ...(result.format !== undefined ? { format: result.format } : {}),
  };

  if (definition.shape.kind === "series") {
    const series = result as SeriesResult;
    return {
      unit: definition.unit,
      currency: series.currency ?? null,
      points: series.points,
      value: series.value,
      previousValue: series.previousValue ?? null,
      ...(series.asOf !== undefined ? { asOf: series.asOf } : {}),
      ...extras,
    };
  }

  if (definition.shape.kind === "total") {
    const total = result as TotalResult;
    return {
      unit: definition.unit,
      currency: total.currency ?? null,
      // One point, at the end of the window rather than at this instant when
      // the provider has said so. No series: that is the whole distinction.
      points: [{ t: total.at ?? at, v: total.value }],
      value: total.value,
      previousValue: total.previousValue ?? null,
      ...(total.asOf !== undefined ? { asOf: total.asOf } : {}),
      ...extras,
    };
  }

  if (definition.shape.kind === "list") {
    const list = result as ListResult;
    const value = list.value ?? list.items.length;
    return {
      unit: definition.unit,
      currency: list.currency ?? null,
      points: [{ t: list.at ?? at, v: value }],
      value,
      previousValue: null,
      asOf: list.asOf ?? at,
      items: list.items,
      ...extras,
    };
  }

  const scalar = result as ScalarResult;
  return {
    unit: definition.unit,
    currency: scalar.currency ?? null,
    // One point, at now. A provider that exposes no history has none, and a
    // flat line invented from a single reading looks like data.
    points: [{ t: scalar.at ?? at, v: scalar.value }],
    value: scalar.value,
    previousValue: null,
    asOf: scalar.asOf ?? at,
    ...extras,
  };
}

/** What a provider declares, minus everything `provider()` derives. */
export interface ProviderOptions<C extends Record<string, unknown>> {
  /** The manifest without `metrics`, which is derived from `metrics` below. */
  manifest: Omit<ProviderManifest, "metrics">;
  credentialSchema: ZodType<C>;
  userInputFields?: readonly string[];
  oauth?: OAuthConfig<C>;
  requestTimeoutMs?: number;
  metrics: MetricDefinition<C>[];
  /**
   * Proves the credentials work, and names the connection.
   *
   * `availableMetrics` is no longer part of this: it was a hand-maintained
   * array of the same ids written one screen above, and a metric added
   * without being added to it is unreachable with nothing failing. Derived
   * from `metrics` now, and a provider that must narrow it — a Stripe
   * restricted key without the Subscriptions permission — returns
   * `unavailableMetrics` instead, which is a statement about this one
   * connection rather than a copy of the catalogue.
   */
  verify(
    ctx: AdapterContext,
    credentials: C,
  ): Promise<Omit<VerifyResult, "availableMetrics"> & { unavailableMetrics?: MetricId[] }>;
  fetchEvents?(ctx: AdapterContext, credentials: C, request: EventRequest): Promise<EventPage>;
}

/**
 * Assembles a `ProviderAdapter` from per-metric definitions.
 *
 * The three things this derives were all hand-written and all forgettable:
 * `manifest.metrics`, `verify`'s `availableMetrics`, and the `fetchMetric`
 * switch. The switch's `default: throw unsupported` arm becomes a missing map
 * key, which cannot drift from the descriptors because it *is* them.
 */
export function provider<C extends Record<string, unknown>>(
  options: ProviderOptions<C>,
): ProviderAdapter<C> {
  const definitions = new Map<string, MetricDefinition<C>>();
  for (const metric of options.metrics) {
    // A `Map` built from the entries would keep the last of a duplicated id
    // and drop the other without a word. Nothing caught that before either:
    // `MetricDescriptor` is a plain `z.array`, so a repeated id parsed, and
    // the result was a widget browser with two rows sharing a SwiftUI
    // `Identifiable` id and a `fetch` that had become dead code.
    if (definitions.has(metric.id)) {
      throw new Error(`${options.manifest.id} declares ${metric.id} twice`);
    }
    definitions.set(metric.id, metric);
  }

  // Built once, at module load, in declaration order — the catalogue's order
  // is the order the widget browser lists them in.
  const descriptors = options.metrics.map((metric) =>
    toDescriptor(metric as MetricDefinition<never>),
  );
  if (descriptors.length === 0) {
    throw new Error(`${options.manifest.id} declares no metrics`);
  }

  const manifest: ProviderManifest = {
    ...options.manifest,
    metrics: descriptors as ProviderManifest["metrics"],
  };

  const ids = options.metrics.map((metric) => metric.id);

  return {
    manifest,
    credentialSchema: options.credentialSchema,
    ...(options.userInputFields !== undefined ? { userInputFields: options.userInputFields } : {}),
    ...(options.oauth !== undefined ? { oauth: options.oauth } : {}),
    ...(options.requestTimeoutMs !== undefined
      ? { requestTimeoutMs: options.requestTimeoutMs }
      : {}),
    ...(options.fetchEvents !== undefined ? { fetchEvents: options.fetchEvents } : {}),

    async verify(ctx, credentials): Promise<VerifyResult> {
      const { unavailableMetrics, ...result } = await options.verify(ctx, credentials);
      const withheld = new Set(unavailableMetrics ?? []);
      return { ...result, availableMetrics: ids.filter((id) => !withheld.has(id)) };
    },

    async fetchMetric(ctx, credentials, request: MetricRequest): Promise<RawSeries> {
      const definition = definitions.get(request.metric);
      if (!definition) {
        throw new ProviderError(
          "unsupported",
          `${options.manifest.name} does not provide ${request.metric}.`,
        );
      }
      const result = await definition.fetch(ctx, credentials, request);
      return toRawSeries(definition as MetricDefinition<never>, ctx, result);
    },
  };
}
