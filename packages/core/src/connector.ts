import { z } from "zod";

/**
 * The primitives a local connector's contract is written in.
 *
 * Defined here rather than imported, because this package is published and an
 * import of `@notch/schemas` would be a module nobody outside the monorepo
 * can resolve. `packages/schemas` re-exports what follows, so there is still
 * exactly one definition — it simply lives on the published side of the line
 * rather than the private one.
 */

/** The bucket a windowed metric is grouped by. */
export const Granularity = z.enum(["hour", "day", "week", "month"]);
export type Granularity = z.infer<typeof Granularity>;

/**
 * What kind of number this is.
 *
 * `currency` means **integer minor units** plus an ISO 4217 code. Never a
 * float: a currency metric returning 20.69 renders as 20 cents.
 */
export const MetricUnit = z.enum(["currency", "count", "ratio", "duration", "bytes"]);
export type MetricUnit = z.infer<typeof MetricUnit>;

/** How a figure is drawn when the unit alone gets it wrong. */
export const MetricFormat = z.object({
  decimals: z.number().int().min(0).max(4).default(0),
  compact: z.boolean().default(true),
  prefix: z.string().max(3).default(""),
  suffix: z.string().max(4).default(""),
});
export type MetricFormat = z.infer<typeof MetricFormat>;

/** One point of a series. `t` is ISO-8601 at the start of the bucket. */
export const MetricPoint = z.object({ t: z.string(), v: z.number() });
export type MetricPoint = z.infer<typeof MetricPoint>;

/**
 * A field rendered by the app — a credential on the connect sheet, or a
 * per-widget parameter in the configure pane.
 *
 * `type` is an enum including `secret` rather than a `masked: true` flag. An
 * app meeting an unknown *type* falls back to a text field; one meeting an
 * unknown *flag* renders a secret in plain sight.
 */
export const AuthField = z.object({
  key: z.string().regex(/^[a-z][a-z0-9_]*$/),
  label: z.string(),
  type: z.enum(["string", "secret", "select", "url", "boolean"]),
  required: z.boolean().default(true),
  placeholder: z.string().optional(),
  help: z.string().optional(),
  pattern: z.string().optional(),
  options: z.array(z.object({ value: z.string(), label: z.string() })).optional(),
  default: z.string().optional(),
});
export type AuthField = z.infer<typeof AuthField>;

/** A connector id. Lower-case, hyphenated, and used as a directory name. */
export const ConnectorId = z.string().regex(/^[a-z0-9][a-z0-9-]{1,47}$/);
export type ConnectorId = z.infer<typeof ConnectorId>;

/** Which app a connector represents, for the mark and the grouping. */
export const AppId = z
  .string()
  .min(1)
  .max(40)
  .regex(/^[a-z0-9][a-z0-9-]*$/);
export type AppId = z.infer<typeof AppId>;

/**
 * A **local connector**: one app, its credentials, and every metric it offers.
 *
 * Authored on the user's own machine — by an agent over MCP, or by hand in a
 * real project — built to a single module, and registered into
 * `~/Library/Application Support/NotchMetrics/connectors/<id>/`. It never
 * reaches our servers and we never see the credential.
 *
 * ## Why this exists beside `PluginManifest`
 *
 * A `PluginManifest` is one metric with its own secrets. Ten numbers from one
 * API therefore meant ten directories, ten copies of the same token, and ten
 * separate approvals. A connector is the unit people actually have: *an
 * account*, with many numbers behind it.
 *
 * ## What it deliberately cannot do
 *
 * **No OAuth.** A refresh needs a client secret, and a client secret on a
 * laptop is a published client secret. `auth` is `AuthField`s — keys, tokens,
 * a subdomain — exactly what the connect form already renders for a built-in
 * connector, which is why it is the same type rather than a new one.
 *
 * **No notifications.** Those are keyed to a server-side integration row.
 *
 * ## The relationship to the built-in connectors
 *
 * This is the same shape as a `ProviderManifest` minus the parts only a
 * server can honour. That is on purpose: the nineteen shipped providers are
 * the worked examples an agent reads, and one set of rules covers both.
 */

/** Our id → the provider's. A metric id is local, so it needs no enum. */
export const LocalMetricId = z
  .string()
  .regex(
    /^[a-z][a-z0-9_]*$/,
    "A metric id is lower-case letters, digits and underscores, starting with a letter.",
  );
export type LocalMetricId = z.infer<typeof LocalMetricId>;

/**
 * What a metric is, as four arms rather than two booleans.
 *
 * The same vocabulary `packages/integrations/src/metric.ts` uses for the
 * built-ins — `scalar`, `series`, `total`, `list`. Declaring the shape is what
 * decides which controls the configure pane shows and what `fetch` must
 * return, and having one vocabulary means an agent that has read a built-in
 * provider already knows this one.
 */
export const LocalMetricShape = z.discriminatedUnion("kind", [
  /** One number for the present. No window, so no range and no comparison. */
  z.object({ kind: z.literal("scalar") }),
  /** A number per bucket over a window. */
  z.object({
    kind: z.literal("series"),
    granularities: z.array(Granularity).nonempty(),
    compare: z.boolean().default(true),
  }),
  /**
   * One number *for* a window, with a delta and no breakdown.
   *
   * For an API that answers a total per call and cannot be bucketed without
   * one request per point.
   */
  z.object({
    kind: z.literal("total"),
    granularities: z.array(Granularity).nonempty(),
    compare: z.boolean().default(true),
  }),
  /** Rows of what just happened. The same rows whatever the range says. */
  z.object({ kind: z.literal("list"), limit: z.number().int().min(1).max(50).default(10) }),
]);
export type LocalMetricShape = z.infer<typeof LocalMetricShape>;

export const LocalMetricDescriptor = z.object({
  id: LocalMetricId,
  label: z.string().min(1).max(60),
  /** What fits in a notch tile. Twelve characters, not a truncation. */
  shortLabel: z.string().max(12),
  unit: MetricUnit,
  currency: z.string().length(3).optional(),
  format: MetricFormat.partial().optional(),
  shape: LocalMetricShape,
  /**
   * How this number is derived, in one sentence.
   *
   * Required for a local connector for the same reason it is required for a
   * built-in: "MRR" is always somebody's definition, and the person reading
   * the tile in six months is usually not the person who wrote the metric.
   */
  methodology: z.string().min(1),
  /**
   * Fields the *widget* supplies — a repository, a project id.
   *
   * Same `AuthField` shape as the credentials form, so the configure pane
   * renders them with no new code.
   */
  params: z.array(AuthField).optional(),
  /** How long a figure stays fresh. Floored by the app regardless. */
  freshnessSeconds: z.number().int().min(60).max(86_400).optional(),
  linkTemplate: z
    .string()
    .regex(/^https:\/\//)
    .optional(),
});
export type LocalMetricDescriptor = z.infer<typeof LocalMetricDescriptor>;

/**
 * How a custom app says what it looks like.
 *
 * A tagged union rather than three optional fields: an app declaring both a
 * symbol and an emoji would otherwise be a question with no answer, and the
 * tag is what lets a future arm be added without the app guessing.
 */
export const ConnectorIconSpec = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("symbol"),
    /**
     * An SF Symbol name, as it appears in Apple's SF Symbols app —
     * `chart.bar.fill`, `shippingbox`, `person.2`.
     */
    name: z
      .string()
      .min(1)
      .max(64)
      .regex(
        /^[a-z0-9]+(\.[a-z0-9]+)*$/,
        "An SF Symbol name is lower-case words separated by dots.",
      ),
    /** A hex tile colour behind the glyph. Defaults to the Custom accent. */
    tint: z
      .string()
      .regex(/^#?[0-9a-fA-F]{6}$/)
      .optional(),
  }),
  z.object({
    type: z.literal("emoji"),
    /** One emoji. Grapheme clusters vary in code-point length, hence 8. */
    value: z.string().min(1).max(8),
  }),
  z.object({
    type: z.literal("app"),
    /**
     * An app Notch Metrics already ships a mark for — `anthropic`, `github`,
     * `stripe`. The icon *and* the tile colour come from that one place, so a
     * connector built against a known service looks like that service without
     * shipping a copy of its logo that drifts from ours.
     *
     * An id we have no mark for falls back to the generic custom mark. It
     * does not grant anything: the Settings row still shows the app's own
     * name and the hosts it reaches.
     */
    appId: AppId,
  }),
  z.object({
    type: z.literal("file"),
    path: z
      .string()
      .regex(
        /^[a-z0-9][a-z0-9._-]{0,39}\.(png|svg)$/,
        "An icon file is a name inside the connector directory, ending .png or .svg.",
      ),
  }),
]);
export type ConnectorIconSpec = z.infer<typeof ConnectorIconSpec>;

/**
 * A credential the **app** holds and hands to a connector, rather than one the
 * user types in.
 *
 * The narrow exception to "credentials come from the connect form". Some
 * things worth measuring are already authenticated on the machine, and the
 * token rotates far too often to paste: a Claude Code OAuth access token lasts
 * about eight hours, so a form field for it would mean re-pasting three times
 * a day.
 *
 * An app only receives one if its manifest asks for it by name, and the
 * Settings row says which — it is visible beside the host allowlist, not
 * ambient. The connector never learns where the token came from or how it is
 * stored.
 */
export const HostCredential = z.enum([
  /**
   * The Claude Code subscription OAuth token, for `api.anthropic.com`'s
   * `/api/oauth/usage` endpoint. Arrives as `ctx.credentials.claude_code_oauth`.
   */
  "claude_code_oauth",
]);
export type HostCredential = z.infer<typeof HostCredential>;

export const LocalConnectorManifest = z
  .object({
    schemaVersion: z.literal(1),
    id: ConnectorId,
    name: z.string().min(1).max(60),
    description: z.string().max(400),
    /** Which app this is, for the mark and the grouping. */
    appId: AppId.default("custom"),
    author: z.string().optional(),

    /**
     * The author's own version, shown in the Custom Apps list.
     *
     * Ours to display, never ours to compare: the app does not upgrade a
     * connector, so this exists so a person can tell which build of their own
     * code is installed. Defaulted rather than required, because a connector
     * written in an afternoon should not have to invent a release process.
     */
    version: z
      .string()
      .regex(/^\d+\.\d+\.\d+$/, "A version is three dot-separated numbers, like 1.0.0.")
      .default("1.0.0"),

    /**
     * The app's icon, declared in the manifest rather than shipped beside it.
     *
     * Three arms, because the author is usually an agent writing one JSON file.
     * Requiring a PNG meant every agent-authored app fell back to the generic
     * mark — an LLM can name an SF Symbol far more easily than it can draw a
     * square image.
     *
     * - `symbol` names an **SF Symbol**, which is what most apps should use:
     *   it is vector, it matches the rest of the interface, and it needs no
     *   file. An unknown name renders the generic mark rather than a blank.
     * - `emoji` is the one-character escape hatch.
     * - `file` is for a real logo, as a **file name** inside the connector
     *   directory — never a path and never a URL. A path would escape the
     *   directory with `../`, and a URL would make the settings pane fetch an
     *   attacker-chosen host on render, before the user has approved anything.
     */
    icon: ConnectorIconSpec.optional(),

    /**
     * How this app authenticates, when it does at all.
     *
     * - `none` — a free or public API, or an app that holds its own credential
     *   in its code. Nothing is asked of the user and no Keychain entry is
     *   read. This is the arm that was missing: an app needing no key still had
     *   to declare an empty `auth` and hope every surface read that as "ask for
     *   nothing" rather than "not configured yet".
     * - `api_key` — the user supplies the fields in `auth`.
     *
     * There is no OAuth arm and there will not be: a refresh needs a client
     * secret, and a client secret on a laptop is a published client secret.
     *
     * Optional, and derived from `auth` when omitted, so an existing manifest
     * keeps working. Declaring `none` alongside fields is refused below rather
     * than silently resolved — two sources disagreeing about whether a
     * credential is needed is how a tile ends up waiting for one for ever.
     */
    authMode: z.enum(["none", "api_key"]).optional(),

    /**
     * Credentials the app supplies, named by the manifest.
     *
     * Separate from `auth`, which is what the *user* is asked for. An app can
     * declare both: a host token for one API and a key the user supplies for
     * another. Declaring one here does not make `authMode` `api_key` — the
     * user is still asked for nothing.
     */
    hostCredentials: z.array(HostCredential).default([]),

    /**
     * What the app asks the user for.
     *
     * `AuthField.type` includes `secret`, so a token renders masked without this
     * schema needing to say so twice. Every value is held in the macOS Keychain
     * and handed to the runner on stdin — never argv, never the environment,
     * never the manifest.
     *
     * Rendered as a form **in the app**, not through a browser. A local app has
     * no redirect URI and nothing to redirect to.
     */
    auth: z.array(AuthField).default([]),

    /**
     * Every host this connector may reach. Exact names, or one leading `*.`.
     *
     * No bare `*`. A connector that may call anywhere is one that can post the
     * credential it was handed to a pastebin, and "it needs the whole internet"
     * is never true of a number.
     */
    allowedHosts: z
      .array(
        z
          .string()
          .regex(/^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/),
      )
      .nonempty(),

    metrics: z.array(LocalMetricDescriptor).nonempty(),

    /** The app floors this at 60s regardless of what the manifest asks for. */
    refreshIntervalSeconds: z.number().int().min(60).max(86_400).default(300),
    timeoutMs: z.number().int().min(1_000).max(20_000).default(8_000),
    entry: z.literal("connector.mjs"),
    createdAt: z.string(),
    updatedAt: z.string(),
  })
  .superRefine((manifest, ctx) => {
    if (manifest.authMode === "none" && manifest.auth.length > 0) {
      ctx.addIssue({
        code: "custom",
        path: ["authMode"],
        message:
          'An app declaring authMode "none" must declare no auth fields. Drop the fields, or set authMode to "api_key".',
      });
    }
  });
export type LocalConnectorManifest = z.infer<typeof LocalConnectorManifest>;

/**
 * Whether this app asks the user for anything.
 *
 * Derived rather than read straight off `authMode`, because the field is
 * optional: a manifest written before it existed says what it needs through
 * `auth` alone.
 */
export function requiresCredentials(manifest: {
  authMode?: "none" | "api_key";
  auth: unknown[];
}): boolean {
  if (manifest.authMode === "none") return false;
  return manifest.auth.length > 0;
}

/**
 * What `verify(ctx, credentials)` must return.
 *
 * Called before the connector is usable, exactly as a built-in's `verify` is
 * called before an integration row is written. A credential that does not work
 * must not become a connector that silently shows nothing.
 */
export const LocalVerifyResult = z.object({
  /** What to call this connection. A login, a store name, an account id. */
  accountLabel: z.string().max(80).nullable().default(null),
  currency: z.string().length(3).nullable().default(null),
  /**
   * Metrics this particular credential cannot reach.
   *
   * Said as a negative so the connector does not restate its own catalogue —
   * the same choice `provider()` makes server-side, and for the same reason:
   * a positive list drifts from the manifest and nothing notices.
   */
  unavailableMetrics: z.array(LocalMetricId).default([]),
});
export type LocalVerifyResult = z.infer<typeof LocalVerifyResult>;

/** One row of a list metric. Mirrors `MetricListItem`. */
export const LocalListItem = z.object({
  id: z.string(),
  t: z.string(),
  label: z.string(),
  detail: z.string().nullable().default(null),
  /** Minor units of `currency`. Never a float. */
  amount: z.number().nullable().default(null),
  currency: z.string().nullable().default(null),
  status: z.string().nullable().default(null),
  state: z.enum(["succeeded", "failed", "running", "neutral"]).optional(),
});
export type LocalListItem = z.infer<typeof LocalListItem>;

/**
 * What `fetchMetric` must return for one metric.
 *
 * Validated after the call, not trusted: a string where a number belongs
 * fails with a message naming the field rather than rendering as `NaN` three
 * days later.
 */
export const LocalMetricResult = z.object({
  value: z.number(),
  previousValue: z.number().nullable().default(null),
  points: z.array(MetricPoint).default([]),
  items: z.array(LocalListItem).optional(),
  currency: z.string().length(3).nullable().default(null),
  note: z.string().max(400).optional(),
  asOf: z.string().optional(),
  format: MetricFormat.partial().optional(),
});
export type LocalMetricResult = z.infer<typeof LocalMetricResult>;

/**
 * The runner's single line of stdout for a connector run.
 *
 * Per metric, because a connector run asks for several at once: one process
 * for the whole tick rather than one per number. That is the difference
 * between a notch of local metrics being a background task and being six Node
 * processes.
 *
 * A failure is per metric too. One metric whose endpoint is down must not
 * blank the other five.
 */
export const LocalMetricOutcome = z.discriminatedUnion("ok", [
  z.object({
    ok: z.literal(true),
    /** The `id` of the request this answers. See `MetricRequest.id`. */
    id: z.string(),
    metric: LocalMetricId,
    result: LocalMetricResult,
  }),
  z.object({
    ok: z.literal(false),
    id: z.string(),
    metric: LocalMetricId,
    code: z.enum(["unsupported", "policy", "timeout", "runtime", "bad_result"]),
    message: z.string(),
  }),
]);
export type LocalMetricOutcome = z.infer<typeof LocalMetricOutcome>;
