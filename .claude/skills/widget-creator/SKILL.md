---
name: widget-creator
description: Add or change a widget — a metric an existing provider offers. Use when somebody wants Stripe to expose trial conversions, GitHub to expose releases, or asks why a widget shows a range picker that does nothing, a chart that stays empty, money that is a thousand times too large, or an error on one range and a number on another. Covers the descriptor contract, which flag turns on which control, which ranges a metric promises to answer, and the sweep that tests every combination. For a whole new provider see `add-integration`; for a user's own one-off metric see `custom-metric`.
---

# Adding a widget

A widget is a **metric on a provider that already exists**. Adding one is four
edits and no app release:

1. `packages/schemas/src/ids.ts` — the `MetricId` enum, if the id is new.
2. `packages/schemas/src/keywords.ts` — search synonyms, if the id is new.
3. `packages/integrations/src/providers/<id>/index.ts` — the descriptor in
   `manifest.metrics`, the id in `verify`'s `availableMetrics`, and a `case`
   in `fetchMetric`.
4. A changeset naming `@notch/integrations`.

Nothing in `apps/mac` changes. The Mac reads the catalogue at runtime, which
is the whole point of `GET /v1/connectors`.

## The descriptor is a UI contract, not documentation

Every field drives something the user sees. Getting one wrong produces a
control that lies rather than a build that fails.

| Field             | What it actually does                                              |
| ----------------- | ------------------------------------------------------------------ |
| `supportsSeries`  | `false` hides the **Chart** control and the sparkline entirely.    |
| `supportsCompare` | With `supportsSeries`, decides whether **Range** is shown at all.  |
| `unit`            | How the number is formatted. `currency` means **minor units**.     |
| `shortLabel`      | The title on the tile. It has about 14 characters.                 |
| `label`           | The name in the widget browser and the configure pane's header.    |
| `methodology`     | Always shown, under Data. This is where "ours differs from theirs" |
| `granularities`   | **Which ranges the pane offers.** See below — this one bites.      |
| `keywords`        | Browser search. Central ones are in `keywords.ts`.                 |

**The rule that matters:** `supportsSeries: false` **and**
`supportsCompare: false` means the configure pane shows no Range and no Chart,
because neither changes anything. Both flags false is correct for a snapshot —
a count of what exists right now, with no history behind it. 19 of the 64
metrics are in that category.

Get this wrong in the generous direction and the user gets a range picker that
does nothing, which is what GitHub's stargazers shipped with.

## Is it a snapshot or a series?

Ask what the provider's API can actually answer, not what sounds better.

- **Snapshot** — "stargazers right now", "active subscriptions", "open
  conversations". The API returns one number for the present. Both flags
  `false`. Return `points: [{ t: ctx.now(), v: value }]` — one point, at now.
  A flat line invented from a single reading looks like data and is not.
- **Series** — "revenue in the window", "signups per day". The API can be
  asked for a range. Both flags `true`, and `granularities` lists what the
  provider can bucket by.

MRR is a snapshot even though it sounds like a rate: it is the current
subscriptions normalised to a month, not a sum over a window.

## Which ranges you are promising

A widget sends a **range** and no granularity. The server derives the bucket
from it, and the configure pane decides which ranges to offer from the ones
your `granularities` covers:

| Range | Bucket the server picks |
| ----- | ----------------------- |
| `24h` | `hour`                  |
| `7d`  | `day`                   |
| `30d` | `day`                   |
| `90d` | `week`                  |
| `12m` | `month`                 |

So `granularities: ["day", "week"]` is a promise to answer `7d`, `30d` and
`90d`, and a refusal to be asked for `24h` or `12m`. Declare what the
provider can actually bucket by — not what sounds complete.

Two ways to get it wrong, and they fail in opposite directions:

- **Too generous.** You declare `month`, the pane offers `12m`, and the
  adapter throws `unsupported` because the provider caps a response at 31
  daily buckets. The user sees an error on one range and a number on another
  and has no way to know which are meant to work. Both LLM connectors
  shipped like this.
- **Too narrow.** The range quietly disappears from the picker. Nothing
  fails, so nothing tells you; the control is just smaller than it should be.

The mapping is duplicated in Swift as `TimeRange.defaultGranularity`, because
the pane cannot wait for the network to lay out a picker.
`ranges.test.ts` pins the two together.

## Test every combination, not the ones you thought of

The bug is always in the combination nobody wrote a case for. Fixture tests
stub by path and assert the parsing, so the _request_ — and the range that
produced it — goes unexamined.

One line sweeps every metric against every range its own manifest offers:

```ts
it("serves every range its manifest offers", async () => {
  expect(await refusedOfferedRanges(myprovider, creds, routes)).toEqual([]);
});
```

`refusedOfferedRanges` is in `test/helpers.ts`. It walks
`manifest.metrics` × `TimeRange`, skips snapshots and anything the metric
does not claim, and returns the refusals — so a failure reads as
`tokens @ 12m (month): That range is longer than the 124 days ...` rather
than as a diff of two objects.

Pass `params` for a metric that needs one before it can answer, and `skip`
with a reason for anything genuinely not sweepable:

```ts
await refusedOfferedRanges(github, creds, routes, {
  params: { stars: { repository: "owner/name" } },
  skip: { releases: "paginates against a fixture we do not have" },
});
```

**It only checks the direction that errors.** An adapter refusing something
its manifest advertises is caught; a manifest that is too narrow is not,
because there is nothing to call. For that, read the picker.

**And it is still a stub.** It proves the adapter and its own manifest agree.
It cannot prove the provider accepts the request — only a real key does that,
which is how a cost report that rejected every window this connector built
got through a green suite. See `add-integration` for the real-key check.

## Traps

**Money is integer minor units plus an ISO 4217 code.** Never a float, never
major units. A `unit: "currency"` metric returning `20.69` renders as 20 cents.

**`granularities` decides which ranges the user can pick.** It was dead
metadata for a long time — every connector declared it and nothing read it —
so the pane offered all five ranges for everything and the ones a provider
could not serve came back as errors on the tile. It is load-bearing now, and
a wrong declaration is a missing control or a broken one rather than a
stale comment.

On a _snapshot_ it is still noise: with both flags false there is no Range
row to populate. Leave an existing one alone; do not add them to a new
snapshot.

**A new `MetricId` is a wire enum.** Swift decodes unknown enum values with a
fallback, so an old app will not break — but the id is in `packages/schemas`
for a reason and the Swift side has hand-written models. Change a wire shape
and you owe `pnpm contracts`, the Swift structs, and all three committed
together. See `AGENTS.md`.

**`availableMetrics` is per connection, not per provider.** `verify` returns
what _this_ account can actually read. A metric in the manifest but missing
from `availableMetrics` is offered and then fails.

## Checking it

```bash
pnpm dev                                   # the Worker serves the catalogue
curl -s localhost:8787/v1/connectors | jq '.categories[].connectors[]
  | select(.id=="github") | .metrics[] | {id, supportsSeries, supportsCompare}'
```

Then look at the configure pane for the metric itself — the controls are what
the flags claim:

```bash
NOTCH_DEBUG_EXPAND=1 NOTCH_DEBUG_CONFIG=<metric-id> \
  apps/mac/build/export/NotchMetrics.app/Contents/MacOS/NotchMetrics
```

A snapshot should show **no Range row and no Chart row** — only the
methodology under Data. Anything else means the flags and the data disagree.

To sweep every metric for that disagreement at once:

```bash
curl -s localhost:8787/v1/connectors | python3 -c "
import sys, json
d = json.load(sys.stdin)
for cat in d['categories']:
    for c in cat['connectors']:
        for m in c['metrics']:
            if not m['supportsSeries'] and not m['supportsCompare']:
                print(f\"snapshot: {c['id']}/{m['id']}\")"
```
