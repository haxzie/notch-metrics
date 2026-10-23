import { z } from "zod";
import type { Granularity, MetricId } from "@notch/schemas";
import { errorForStatus } from "../../http.ts";
import { bucketSum } from "../../normalise.ts";
import type {
  AdapterContext,
  HttpResponse,
  MetricRequest,
  ProviderAdapter,
  RawSeries,
  VerifyResult,
} from "../../types.ts";
import { metricsFor, provider, type SeriesResult } from "../../metric.ts";
import { ProviderError } from "../../types.ts";
import { manifest } from "./manifest.ts";

export { manifest };

export const credentialSchema = z.object({
  api_key: z.string().min(8),
  // Digits or empty. Empty means "whichever project this key is currently
  // pointed at", resolved once per call from /api/users/@me/.
  project_id: z.string().regex(/^\d*$/, "A PostHog project ID is a number.").optional().default(""),
  region: z.enum(["us", "eu"]).default("us"),
});
export type PosthogCredentials = z.infer<typeof credentialSchema>;

function host(creds: PosthogCredentials): string {
  return creds.region === "eu" ? "eu.posthog.com" : "us.posthog.com";
}

/**
 * 401 names the region as well as the key.
 *
 * US and EU are separate databases, so a US key presented to the EU host is
 * not a wrong password — it is a key that does not exist there, and PostHog
 * answers the same 401 either way. Somebody who picked the wrong region
 * would otherwise spend the afternoon rolling a key that was fine.
 */
function errorFor(creds: PosthogCredentials, response: HttpResponse): ProviderError {
  if (response.status === 401) {
    return new ProviderError(
      "auth_failed",
      `PostHog rejected this key. Check it is a ${creds.region.toUpperCase()} Cloud key — the other region answers 401 too.`,
    );
  }
  return errorForStatus(host(creds), response);
}

async function request<T>(
  ctx: AdapterContext,
  creds: PosthogCredentials,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await ctx.http(`https://${host(creds)}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${creds.api_key}`,
      accept: "application/json",
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...init.headers,
    },
  });
  if (!response.ok) throw errorFor(creds, response);
  return response.json<T>();
}

interface Team {
  id: number;
  name?: string | null;
}

interface Me {
  team?: Team | null;
  organization?: { name?: string | null } | null;
}

async function me(ctx: AdapterContext, creds: PosthogCredentials): Promise<Me> {
  return request<Me>(ctx, creds, "/api/users/@me/");
}

/**
 * The project every query runs against.
 *
 * A typed id wins, so somebody with several projects can point two
 * connections at two of them. Otherwise the key's own current project —
 * which is a plain CRUD call, not a `/query`, so it does not touch the
 * hourly read budget that the query endpoint bills against.
 */
async function resolveProject(ctx: AdapterContext, creds: PosthogCredentials): Promise<string> {
  if (creds.project_id) return creds.project_id;
  const id = (await me(ctx, creds)).team?.id;
  if (id === undefined || id === null) {
    throw new ProviderError("unsupported", "This key has no default project. Enter a project ID.");
  }
  return String(id);
}

interface QueryResponse {
  results?: unknown[][];
  columns?: string[];
}

/**
 * One HogQL query against a project.
 *
 * HogQL rather than a `TrendsQuery`: the trends response is typed
 * `Record<string, any>` in PostHog's own schema and its field names are not
 * in the docs, where a `SELECT` we wrote returns columns we named. Every
 * query here is a bounded aggregate — PostHog bills `/query` against an
 * hourly *bytes read* budget, so an unbounded scan is not merely slow, it
 * spends somebody's quota.
 */
async function hogql(
  ctx: AdapterContext,
  creds: PosthogCredentials,
  project: string,
  query: string,
  name: string,
): Promise<unknown[][]> {
  const body = await request<QueryResponse>(ctx, creds, `/api/projects/${project}/query/`, {
    method: "POST",
    // `name` lands in PostHog's own query_log, so a user looking at what is
    // hitting their project sees us by name rather than an anonymous SELECT.
    body: JSON.stringify({ query: { kind: "HogQLQuery", query }, name: `notch:${name}` }),
  });
  return body.results ?? [];
}

/** How a metric is counted, and out of which table. */
interface Spec {
  table: "events" | "persons";
  /** The time column bucketed and filtered on. */
  time: string;
  /** The aggregate. `count()` sums; a `DISTINCT` does not — see `distinct`. */
  aggregate: string;
  /** Extra `WHERE` terms, already safe to inline. */
  filter?: string;
  /**
   * Whether the window total differs from the sum of its buckets.
   *
   * A distinct count does: one person active on three days is three bars and
   * one user. Those metrics pay for a second query rather than reporting a
   * headline that is the sum of its own chart and wrong.
   */
  distinct: boolean;
}

/**
 * `toStartOfHour` for an hour, `toStartOfDay` for everything else.
 *
 * Weeks and months are rolled up from days in `bucketSum` rather than asked
 * of ClickHouse, which keeps this to the one-argument form of each function
 * and puts every timezone decision in one place.
 */
function floorOf(granularity: Granularity): string {
  return granularity === "hour" ? "toStartOfHour" : "toStartOfDay";
}

/** Epoch seconds. `toDateTime(<int>)` is the one date literal with no timezone in it. */
function seconds(date: Date): number {
  return Math.floor(date.getTime() / 1000);
}

/**
 * The window a query covers: the requested one, widened to include the
 * compare window so both come back in a single call.
 */
function span(request: MetricRequest): { start: Date; end: Date } {
  const windowMs = request.to.getTime() - request.from.getTime();
  return {
    start: request.comparePrevious ? new Date(request.from.getTime() - windowMs) : request.from,
    end: request.to,
  };
}

function range(spec: Spec, start: Date, end: Date): string {
  const terms = [
    `${spec.time} >= toDateTime(${seconds(start)})`,
    `${spec.time} < toDateTime(${seconds(end)})`,
  ];
  if (spec.filter) terms.push(spec.filter);
  return terms.join(" AND ");
}

function toNumber(value: unknown): number {
  const n = typeof value === "string" ? Number(value) : value;
  return typeof n === "number" && Number.isFinite(n) ? n : 0;
}

/** One row per bucket, as epoch seconds and a count. */
async function buckets(
  ctx: AdapterContext,
  creds: PosthogCredentials,
  project: string,
  spec: Spec,
  metric: MetricId,
  request: MetricRequest,
): Promise<{ at: Date; amount: number }[]> {
  const { start, end } = span(request);
  const floor = floorOf(request.granularity);
  const rows = await hogql(
    ctx,
    creds,
    project,
    `SELECT toUnixTimestamp(${floor}(${spec.time})) AS bucket, ${spec.aggregate} AS value ` +
      `FROM ${spec.table} WHERE ${range(spec, start, end)} ` +
      `GROUP BY bucket ORDER BY bucket`,
    `${metric}.series`,
  );
  return rows
    .map((row) => ({ at: new Date(toNumber(row[0]) * 1000), amount: toNumber(row[1]) }))
    .filter((row) => !Number.isNaN(row.at.getTime()));
}

/**
 * Both windows' de-duplicated totals, in one query.
 *
 * Grouping on the comparison itself rather than asking twice: the rows are
 * already being scanned, and a second round trip would bill the read budget
 * for the same bytes again.
 */
async function windowTotals(
  ctx: AdapterContext,
  creds: PosthogCredentials,
  project: string,
  spec: Spec,
  metric: MetricId,
  request: MetricRequest,
): Promise<{ current: number; previous: number | null }> {
  const { start, end } = span(request);
  const rows = await hogql(
    ctx,
    creds,
    project,
    `SELECT ${spec.time} >= toDateTime(${seconds(request.from)}) AS is_current, ` +
      `${spec.aggregate} AS value FROM ${spec.table} ` +
      `WHERE ${range(spec, start, end)} GROUP BY is_current`,
    `${metric}.total`,
  );

  let current = 0;
  let previous = 0;
  for (const row of rows) {
    // ClickHouse serialises the boolean as 0/1; tolerate a real boolean too.
    if (row[0] === true || toNumber(row[0]) === 1) current = toNumber(row[1]);
    else previous = toNumber(row[1]);
  }
  return { current, previous: request.comparePrevious ? previous : null };
}

const { series } = metricsFor<PosthogCredentials>();

/**
 * One HogQL metric.
 *
 * The five differ only by a `Spec` — which table, which time column, which
 * aggregate, and whether a distinct count makes the window total something
 * other than the sum of its buckets. That table used to be `SPECS`, keyed on
 * metric id and read by both the switch and `verify`; each metric carries its
 * own now.
 */
function hogqlMetric(options: {
  id: MetricId;
  label: string;
  shortLabel: string;
  granularities: [Granularity, ...Granularity[]];
  methodology: string;
  spec: Spec;
}) {
  return series({
    id: options.id,
    label: options.label,
    shortLabel: options.shortLabel,
    unit: "count",
    granularities: options.granularities,
    compare: true,
    methodology: options.methodology,

    async fetch(ctx, creds, request: MetricRequest): Promise<SeriesResult> {
      const spec = options.spec;
      const project = await resolveProject(ctx, creds);
      const rows = await buckets(ctx, creds, project, spec, options.id, request);
      const current = rows.filter((row) => row.at.getTime() >= request.from.getTime());

      const points = bucketSum(current, {
        from: request.from,
        to: request.to,
        granularity: request.granularity,
        timeZone: ctx.timeZone,
      });

      if (!spec.distinct) {
        const sum = (set: typeof rows) => set.reduce((total, row) => total + row.amount, 0);
        return {
          points,
          value: sum(current),
          // Gated on the flag rather than on what came back: a row from before
          // the window would otherwise become a delta nobody asked for.
          previousValue: request.comparePrevious
            ? sum(rows.filter((row) => row.at.getTime() < request.from.getTime()))
            : null,
        };
      }

      // A second query rather than a headline that is the sum of its own
      // chart and wrong: one person active on three days is three bars and
      // one user.
      const totals = await windowTotals(ctx, creds, project, spec, options.id, request);
      return { points, value: totals.current, previousValue: totals.previous };
    },
  });
}

export const activeUsers = hogqlMetric({
  id: "active_users",
  label: "Active users",
  shortLabel: "Users",
  granularities: ["hour", "day", "week", "month"],
  methodology:
    "People with at least one event in the window, de-duplicated. The headline counts each person once across the whole window, so the bars do not add up to it: one person on three days is one user and three bars. Days are your PostHog project's timezone, so the figures match its own dashboards.",
  spec: {
    table: "events",
    time: "timestamp",
    // A distinct count, so the window total is not the sum of its buckets.
    aggregate: "count(DISTINCT person_id)",
    distinct: true,
  },
});

export const newUsers = hogqlMetric({
  id: "new_users",
  label: "New users",
  shortLabel: "New",
  granularities: ["day", "week", "month"],
  methodology:
    "Person profiles PostHog first created in the window. Anonymous visitors who are never identified do not create one, so this counts people PostHog can tell apart rather than every first visit.",
  spec: { table: "persons", time: "created_at", aggregate: "count()", distinct: false },
});

export const events = hogqlMetric({
  id: "events",
  label: "Events",
  shortLabel: "Events",
  granularities: ["hour", "day", "week", "month"],
  methodology: "Every event recorded in the window, of every name.",
  spec: { table: "events", time: "timestamp", aggregate: "count()", distinct: false },
});

export const pageviews = hogqlMetric({
  id: "pageviews",
  label: "Pageviews",
  shortLabel: "Views",
  granularities: ["hour", "day", "week", "month"],
  methodology: "`$pageview` events in the window. Repeat views by one person all count.",
  spec: {
    table: "events",
    time: "timestamp",
    aggregate: "count()",
    filter: "event = '$pageview'",
    distinct: false,
  },
});

export const sessions = hogqlMetric({
  id: "sessions",
  label: "Sessions",
  shortLabel: "Sessions",
  granularities: ["hour", "day", "week", "month"],
  methodology:
    "Distinct `$session_id`s seen in the window. The headline de-duplicates across the whole window, so a session spanning midnight is one session and two bars.",
  spec: {
    table: "events",
    time: "timestamp",
    aggregate: "count(DISTINCT properties.$session_id)",
    filter: "properties.$session_id IS NOT NULL",
    distinct: true,
  },
});

export const posthog = provider({
  metrics: [activeUsers, newUsers, events, pageviews, sessions],
  manifest,
  credentialSchema,

  // Every number here is a HogQL aggregate over the event table, not a row
  // read, and a ninety-day one measured five to nine and a half seconds
  // across this connector's metrics. The default eight was inside that
  // spread, so the same widget timed out or answered depending on the day.
  requestTimeoutMs: 15_000,

  async verify(ctx, creds) {
    // Names the connection and proves `user:read` in one call.
    const identity = await me(ctx, creds);
    const project = creds.project_id || (identity.team?.id ? String(identity.team.id) : "");
    if (!project) {
      throw new ProviderError(
        "unsupported",
        "This key has no default project. Enter a project ID.",
      );
    }

    // A literal, so it proves `query:read` and that this key can see this
    // project without reading a single event row off the budget.
    try {
      await hogql(ctx, creds, project, "SELECT 1", "verify");
    } catch (error) {
      if (error instanceof ProviderError && error.code === "auth_failed") {
        throw new ProviderError(
          "auth_failed",
          "This key cannot run queries on that project. Give it the Query Read scope, and check the project ID.",
        );
      }
      throw error;
    }

    const projectName = identity.team?.name?.trim();
    const orgName = identity.organization?.name?.trim();
    // "Acme — Website" when both are known, so two projects in one org are
    // still told apart and two orgs with a "Website" each are too.
    const label =
      projectName && orgName && projectName !== orgName
        ? `${orgName} — ${projectName}`
        : (projectName ?? orgName ?? `Project ${project}`);

    return {
      accountLabel: label,
      currency: null,
      // No `availableMetrics`: it was `Object.keys(SPECS)`, the same table
      // the switch read. Derived from the metrics now, so the catalogue and
      // what a connection offers cannot disagree.
    };
  },
});
