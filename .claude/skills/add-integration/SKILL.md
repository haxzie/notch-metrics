---
name: add-integration
description: Add a payment or SaaS provider. Use when someone wants to support Paddle, Polar, Chargebee, Gumroad or similar, asks how the Mac app learns about a new provider, or is about to add a vendor SDK. A manifest, a TypeScript adapter and a Swift one that is what actually runs — it ships in a Mac release, not a deploy, and it touches the credential path, which is where a mistake costs money or leaks a key.
---

# Adding a provider

**This is now a Mac release, not a deploy.** It used to be four files and a
`wrangler deploy`, because the Worker held the credentials and did the
fetching. It does neither now: keys live in each Mac's Keychain, the adapter
that reads them is compiled into the app, and the catalogue ships as a bundled
resource. Nothing a server serves can add a connector any more.

So it is eight things:

**The manifest and the TypeScript adapter.** Still the source of truth for
what a connector _is_, and still what the website's `/sources` pages and the
bundled catalogue are generated from.

1. `packages/integrations/src/providers/<id>/manifest.ts`
2. `packages/integrations/src/providers/<id>/index.ts`
3. One line in `src/registry.ts` — typed as a total record, so a missing
   registration is a compile error rather than a runtime surprise
4. `test/<id>.test.ts` with recorded fixtures

**The Swift adapter.** This is what actually runs. Without it the connector
appears in the list and cannot be connected: `ProviderRegistry.isLocal`
returns false and the Connect button falls back to a browser flow that no
longer exists.

5. `apps/mac/Kit/Sources/Providers/<Name>Provider.swift` — `LocalProvider`
   conformance: `id`, `allowedHosts`, `verify`
6. `apps/mac/Kit/Sources/Providers/<Name>Metrics.swift` — `fetch` and the
   metrics, with the wire types nested in the extension
7. `apps/mac/Kit/Tests/ProvidersTests/<Name>Tests.swift`
8. One line in `Kit/Sources/Providers/ProviderRegistry.swift`

**New ids go in the enums first.** `ProviderId` and `MetricId` in
`packages/schemas/src/ids.ts` are closed enums, and the registry will not
compile until yours is in them.

**The icon.** Drop `<id>.svg` in `packages/ui/assets/connectors/overrides/`
and run `node scripts/sync-connector-icons.mjs`. `registry.test.ts` fails by
name if you forget, and tells you the path.

**Then regenerate the bundled catalogue**, or the app ships listing the old
fields:

```bash
pnpm catalogue      # also run by pnpm mac:gen
```

## Keep the two adapters honest

A widget must not change its number because the fetch moved. Match the
bucketing, the currency exclusion, the monthly normalisation and the
pagination caps exactly, and port the _reasoning_ in the comments rather than
just the arithmetic. `MetricWindow.comparePrevious` is the one thing with no
TypeScript equivalent: when true, widen the window backwards by its own
length, put the earlier half in `previousValue`, and sum both halves from the
rows rather than from the buckets.

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
pnpm mac:gen && pnpm mac:test              # the Swift adapter and the bundled catalogue
pnpm mac:run                               # connect it for real, in the notch
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
