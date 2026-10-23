---
"@notch/integrations": patch
---

Metrics are defined per metric, by a factory, instead of as a manifest entry
and a far-away `case`.

A widget was three edits in one file that nothing connected: a descriptor in
`manifest.metrics`, its id in `verify`'s hand-written `availableMetrics`, and
a `case` in a `fetchMetric` switch some five hundred lines below. That split
is why a `granularities` promising a bucket the `case` throws on was invisible
until it reached a tile, and why a metric added without being copied into the
array was simply unreachable.

`scalarMetric`, `seriesMetric` and `listMetric` take a descriptor and its
`fetch` together, and `provider()` derives all three of those from the list it
is given. One factory per shape rather than one `metric({ shape })`, because
the discriminant has to be in the function name for inference to run forwards
— otherwise a mistake inside `fetch` reports as "no overload matches this
call" against line one of a forty-line literal.

Shape replaces the two booleans internally. `supportsSeries: false` and
`supportsCompare: false` described both GitHub's stars and its CI feed for
entirely unrelated reasons — one has no history, the other is a feed with no
window — and nothing in the pair said which. It also puts `granularities` on
the two arms where anything reads it: on a snapshot it was decoration that
looked load-bearing, which is how both LLM connectors came to offer a range
they cannot answer.

All nineteen providers are converted, and the shared payments feed with them:
`recentPaymentsMetric` replaces a descriptor spread into six manifests and a
builder called from six `case` arms, with a `totalIn` hook for the one
provider — Shopify — whose feed totals in the store's currency rather than the
user's.

Nothing crosses the wire differently. The catalogue still carries
`supportsSeries`, `supportsCompare` and `granularities`, derived, so installed
apps are unaffected, no app release is involved and no contract is
regenerated.

Converting turned up a fourth shape I had not expected. `total` is a number
_for_ a window, with a delta and no breakdown: RevenueCat's revenue comes from
an endpoint that answers one figure per call, so a thirty-point sparkline
would be a minute of its rate budget, and YouTube's subscriber count has a
running total from one API and daily deltas from another with no way to join
them into a line. Both are the `supportsSeries: false, supportsCompare: true`
pair, which the first draft of this change assumed was nonsense and would have
flattened into a plain snapshot — losing a working comparison on two metrics.

Two things this now catches that nothing did. A provider declaring one metric
id twice throws at module load rather than silently dropping one and leaving
two browser rows sharing an `Identifiable` id. And a `fetch` returning the
wrong thing for its shape is a compile error, instead of a snapshot
hand-rolling `points` and inventing a flat line.

Three side tables keyed on metric id are gone with the switches that read
them: PostHog's `SPECS`, Amplitude's `SPECS`, YouTube's `figure`/`UNITS`/
`SERVED` trio, and the `METRICS` lookups in Plausible and Google Analytics.
Each had to agree with its manifest, and several quietly did not.

The only descriptor change on the wire is `granularities` on a metric with no
window, which now reads as every bucket. Nothing interprets it once
`supportsSeries` is false, and installed apps run `clampRange()` whether the
Range row is shown or not — so a narrow list there would silently rewrite the
stored range of a snapshot widget the first time its pane opened.
