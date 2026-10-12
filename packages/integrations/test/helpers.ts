import { DEFAULT_GRANULARITY, RANGE_DURATION_MS, TimeRange } from "@notch/schemas";
import type { AdapterContext, HttpResponse, ProviderAdapter } from "../src/types.ts";

const TIME_RANGES = TimeRange.options;

/**
 * A fake `http` that answers from a routing table instead of the network.
 *
 * Keys are matched as substrings of the full URL *and* of a string request
 * body, longest first, so a test can say `"/subscriptions?status=active"`
 * without rebuilding Stripe's query ordering — and can route a GraphQL
 * provider, where every call is a POST to the same URL, by its operation
 * name.
 */
export function stubContext(
  routes: Record<string, unknown | ((url: URL, init?: RequestInit) => unknown)>,
  overrides: Partial<AdapterContext> = {},
): AdapterContext & { calls: string[] } {
  const calls: string[] = [];
  const keys = Object.keys(routes).sort((a, b) => b.length - a.length);

  return {
    calls,
    now: () => new Date("2026-10-05T12:00:00.000Z"),
    timeZone: "UTC",
    preferredCurrency: "USD",
    signal: new AbortController().signal,
    log: () => {},
    async http(url: string, init?: RequestInit): Promise<HttpResponse> {
      calls.push(url);
      const parsed = new URL(url);
      const sent = typeof init?.body === "string" ? init.body : "";
      const haystack = `${url} ${sent}`;
      const key = keys.find((k) => haystack.includes(k));
      if (key === undefined) throw new Error(`no stub for ${url}`);
      const entry = routes[key]!;
      const body =
        typeof entry === "function"
          ? (entry as (u: URL, i?: RequestInit) => unknown)(parsed, init)
          : entry;
      if (body && typeof body === "object" && "__status" in body) {
        const status = (body as { __status: number }).__status;
        return {
          ok: false,
          status,
          headers: new Headers((body as { __headers?: Record<string, string> }).__headers ?? {}),
          json: <T>() => Promise.resolve({} as T),
          text: () => Promise.resolve(""),
        };
      }
      return {
        ok: true,
        status: 200,
        headers: new Headers(),
        // The cast is the point of a stub: the fixture *is* whatever the
        // caller claims it is, and the test asserts on the derivation rather
        // than on the shape.
        json: <T>() => Promise.resolve(body as T),
        text: () => Promise.resolve(JSON.stringify(body)),
      };
    },
    ...overrides,
  } as AdapterContext & { calls: string[] };
}

export function sub(options: {
  id: string;
  amount: number;
  interval?: string;
  intervalCount?: number;
  quantity?: number;
  currency?: string;
  percentOff?: number;
  created?: number;
  canceledAt?: number | null;
}) {
  return {
    id: options.id,
    status: "active",
    created: options.created ?? 1_700_000_000,
    canceled_at: options.canceledAt ?? null,
    currency: options.currency ?? "usd",
    discounts: options.percentOff ? [{ coupon: { percent_off: options.percentOff } }] : [],
    items: {
      data: [
        {
          quantity: options.quantity ?? 1,
          price: {
            unit_amount: options.amount,
            currency: options.currency ?? "usd",
            recurring: {
              interval: options.interval ?? "month",
              interval_count: options.intervalCount ?? 1,
            },
          },
        },
      ],
    },
  };
}

/**
 * `noUncheckedIndexedAccess` makes every array index `T | undefined`, which is
 * correct and tedious in tests where the row is known to exist.
 */
export function scalar<T>(value: T | undefined, what = "value"): T {
  if (value === undefined) throw new Error(`expected a ${what}`);
  return value;
}

/**
 * Every range the manifest offers, for every metric, put through the adapter.
 *
 * The invariant it checks is the one no fixture test can: **an adapter must
 * not refuse a combination its own manifest advertises.** A widget sends a
 * range and no granularity, the server derives the bucket from
 * `DEFAULT_GRANULARITY`, and the configure pane decides which ranges to offer
 * from the metric's declared `granularities` — so a metric claiming `day` has
 * promised to answer "7d" and "30d", and a tile is the only place anyone
 * finds out it does not.
 *
 * Written as a sweep rather than a case per combination because the failure
 * is always in the combination nobody thought to write by hand: OpenAI and
 * Claude shipped offering "12m" on everything and "24h" on spend, and both
 * came back as errors on the tile.
 *
 * Returns the refusals, so the caller asserts an empty array and reads the
 * offenders straight out of the diff.
 */
export async function refusedOfferedRanges<Credentials extends Record<string, unknown>>(
  adapter: Pick<ProviderAdapter<Credentials>, "manifest" | "fetchMetric">,
  credentials: Credentials,
  routes: Parameters<typeof stubContext>[0],
  options: {
    /** Params a metric needs before it can answer — GitHub's repository. */
    params?: Record<string, Record<string, string>>;
    /** `provider.metric` entries to leave out, each with a reason. */
    skip?: Record<string, string>;
  } = {},
): Promise<string[]> {
  const refused: string[] = [];

  for (const metric of adapter.manifest.metrics) {
    // A snapshot has no window, so its range is not a promise about anything.
    if (!metric.supportsSeries && !metric.supportsCompare) continue;
    if (options.skip?.[metric.id]) continue;

    for (const range of TIME_RANGES) {
      const granularity = DEFAULT_GRANULARITY[range];
      if (!metric.granularities.includes(granularity)) continue;

      const ctx = stubContext(routes);
      const to = ctx.now();
      const from = new Date(to.getTime() - RANGE_DURATION_MS[range]);
      try {
        await adapter.fetchMetric(ctx, credentials, {
          metric: metric.id,
          granularity,
          from,
          to,
          comparePrevious: true,
          wantSeries: true,
          params: options.params?.[metric.id] ?? {},
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        refused.push(`${metric.id} @ ${range} (${granularity}): ${message}`);
      }
    }
  }

  return refused;
}
