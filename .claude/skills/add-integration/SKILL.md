---
name: add-integration
description: Add a payment or SaaS provider to packages/integrations. Use when someone wants to support Paddle, Polar, Chargebee, Gumroad or similar, asks how the Mac app learns about a new provider, or is about to add a vendor SDK to the Worker. Four files and no app release — but it touches the credential path, which is where a mistake costs money or leaks a key.
---

# Adding a provider

Four things, and deliberately no more:

1. `packages/integrations/src/providers/<id>/manifest.ts`
2. `packages/integrations/src/providers/<id>/index.ts`
3. One line in `src/registry.ts`, and a bump of `REGISTRY_VERSION`
4. `test/<id>.test.ts` with recorded fixtures

No route changes. No Mac release — the settings UI renders from
`GET /v1/providers`, so a deployed Worker is the whole shipping story.

## The adapter

```ts
export const paddle: ProviderAdapter<PaddleCredentials> = {
  manifest,
  credentialSchema,                      // the only schema for the form's output
  verify(ctx, creds) { … },              // called BEFORE any row is written
  fetchMetric(ctx, creds, request) { … },
};
```

`verify` runs before the integration row exists. A key that does not work must
not become a row that silently never syncs and shows a zero for a week.

Narrow rather than fail: if a restricted key can read charges but not
subscriptions, return the smaller `availableMetrics` instead of rejecting the
connection. Telling somebody their perfectly good key is broken is worse than
greying out two metrics.

## `ctx.http` is the only network access

A bare `fetch` in an adapter is reviewable as a bug. `ctx.http` enforces the
manifest's `allowedHosts`, a timeout, a byte cap and `redirect: "manual"` with
a per-hop host re-check.

That last one is the point: `fetch` re-sends request headers across a
same-protocol redirect, so a provider that 302s to a host you do not control
would have the user's API key replayed to it, with none of our code involved.

## No vendor SDKs

Three Node-shaped SDKs in a Worker bundle, for a dozen GETs, when the HTTP
shape is the contract either way. Hand-roll it.

## Things that are easy to get wrong

- **Money is integer minor units** plus an ISO 4217 code. Never a float.
- **`value` is not always `sum(points)`.** MRR is a snapshot of the
  subscription book; revenue is a total over the window.
- **Bound the page walk.** An account with 50 000 subscriptions cannot be
  totalled inside a Worker's CPU budget. The cap turns a 30-second death into
  `ProviderError("unsupported", …)` that says what is wrong.
- **Exclude other currencies, do not convert them.** Summing at 1:1 is the kind
  of wrong that looks right. Say so in the series `note`.
- **Explicit test/live mode** where the provider has one. A live key against a
  test host answers 401, which reads as a bad key and costs an hour.

## The manifest is the UI

`AuthField.type` is an enum including `secret` rather than a `masked: true`
flag, so an app that meets an unknown type falls back to a text field rather
than rendering a secret in plain sight.

`MetricDescriptor.methodology` is required. "MRR" is always somebody's
definition and it is the one number users will argue about.

Set `status: "coming_soon"` until the adapter actually works — the settings UI
lists it and greys it out, which is better than a connect button that fails.

`REGISTRY_VERSION` needs nothing: it is the ETag, and it is now hashed from
the manifests themselves. It used to be hand-maintained, and the failure that
changed it is worth knowing — two connectors were promoted from `coming_soon`
to `stable` without touching it, so every client that revalidated got a 304
and kept showing them as unavailable, forever.

## Before it ships

```bash
pnpm --filter @notch/integrations test     # registry.test.ts checks every manifest parses
pnpm --filter @notch/api test
pnpm --filter @notch/api dev &
curl -s localhost:8787/v1/providers | jq '.providers[] | {id, status}'
```

Your test file owes one sweep as well as its fixtures:

```ts
it("serves every range its manifest offers", async () => {
  expect(await refusedOfferedRanges(myprovider, creds, routes)).toEqual([]);
});
```

Fixtures assert the parsing; this asserts that the adapter answers every
range its own `granularities` advertises. The combination nobody writes a
case for is the one that reaches a tile. See `widget-creator` for what the
declaration promises.

Then connect a real key and confirm the numbers match the provider's own —
in **test mode** where the provider has one.

A green suite does not mean the provider accepts the request. Every stub
answers whatever the fixture says, so a query string the API rejects outright
passes every test in the file: the LLM connectors shipped asking their cost
report for a window it refuses, and the first thing anyone saw was a 400 on
connect that read like a bad key. Walk every metric and every range once
against a real key before calling it done.

## OAuth connectors whose tokens expire

If the provider issues an access token with an `expires_in`, the adapter's
`oauth` block **must** do three things, or the connection silently dies the
first time the token does — for GitHub that was every eight hours, and the
only symptom was "needs reconnecting":

1. Write `expires_at` (Unix ms, as a decimal string — see `EXPIRES_AT_FIELD`)
   and the `refresh_token` into the credential blob from `exchangeCode`.
2. Declare `refresh: { leadTimeMs, minIntervalMs }`. Lead time is how early
   to rotate; be generous, the old token keeps working until the new one is
   issued. The floor is what stops a bug from looping on the token endpoint
   and getting the whole client id throttled.
3. Implement `refreshCredentials`. Throw `OAuthReauthRequiredError` only for
   the provider's unambiguous "start over" answer (`bad_refresh_token`,
   `invalid_grant`). Any other failure is a strike, retried on the next tick.

`apps/api/src/lib/token-refresh.ts` does the rest: the five-minute cron sweeps
rows inside their lead window using the mirrored `token_expires_at` column, and
every metric fetch runs the same check first so a request does not race the
cron. Nothing to wire up per connector. `isRefreshDue` is the one place
staleness is decided — do not re-check expiry inside the adapter.
