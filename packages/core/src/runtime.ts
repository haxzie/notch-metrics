import type { Granularity } from "./connector.ts";

/**
 * What the runner hands a connector.
 *
 * Declared here so an author writing TypeScript gets the shape in their
 * editor. Nothing is imported at run time — the runner supplies this object —
 * so a connector can be plain JavaScript with no dependency on this package
 * at all. The types are a convenience, not a requirement.
 */
export interface ConnectorContext {
  /**
   * Only the keys the manifest's `auth` declares.
   *
   * Filtered and frozen before the connector's code runs, so a credential it
   * never asked for is not readable by it.
   */
  credentials: Readonly<Record<string, string>>;

  /** The window this request is for. */
  timeRange: { from: string; to: string; granularity: string; timeZone: string };

  /** Aborted when the run exceeds the manifest's `timeoutMs`. */
  signal: AbortSignal;

  /** Lands in the run's logs, not on the tile. */
  log(message: string, fields?: Record<string, unknown>): void;

  /**
   * The **only** network access. A bare `fetch` bypasses every guarantee here.
   *
   * Enforces the manifest's `allowedHosts`, requires https, refuses private
   * and loopback addresses, follows at most three redirects re-checking the
   * host on each hop, and caps a response at 4 MB.
   *
   * That redirect handling is the part worth knowing about: `fetch` re-sends
   * request headers across a same-protocol redirect, so a server that 302s to
   * a host outside the allowlist would otherwise be handed the credential by
   * the runtime, with none of the connector's code involved.
   */
  http(
    url: string,
    init?: { method?: string; headers?: Record<string, string>; body?: string },
  ): Promise<{
    ok: boolean;
    status: number;
    headers: Record<string, string>;
    json<T = unknown>(): Promise<T>;
    text(): Promise<string>;
  }>;
}

/** What one metric is being asked for. */
export interface MetricRequest {
  /** The `id` of one of the manifest's declared metrics. */
  metric: string;
  /** Whatever the widget supplied for this metric's declared `params`. */
  params: Record<string, string>;
  range: string;
  granularity: Granularity | string;
  from: string;
  to: string;
  /** Whether the previous equal-length window is wanted for the delta. */
  comparePrevious: boolean;
}

/**
 * The two functions a connector module exports.
 *
 * Both may be written as `export async function`, or exported from a bundle
 * as `export { verify, fetchMetric }` — a built project is expected and the
 * registration lint accepts either.
 */
export interface ConnectorModule {
  /**
   * Proves the credential works and names the connection.
   *
   * Runs before the connector is registered. Throw to reject: a key that does
   * not work must not become a connector that silently shows nothing.
   */
  verify(ctx: ConnectorContext): Promise<{
    accountLabel?: string | null;
    currency?: string | null;
    /** Metrics *this* credential cannot reach. Said as a negative. */
    unavailableMetrics?: string[];
  }>;

  /**
   * Answers one metric. Called once per requested metric, in one process —
   * do not assume a fresh process per metric.
   */
  fetchMetric(
    ctx: ConnectorContext,
    request: MetricRequest,
  ): Promise<{
    value: number;
    previousValue?: number | null;
    points?: { t: string; v: number }[];
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
    note?: string;
    asOf?: string;
  }>;
}
