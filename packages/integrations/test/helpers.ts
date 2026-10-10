import type { AdapterContext, HttpResponse } from "../src/types.ts";

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
