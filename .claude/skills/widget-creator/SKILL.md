---
name: widget-creator
description: Add or change a widget — a metric an existing provider offers. Use when somebody wants Stripe to expose trial conversions, GitHub to expose releases, or asks why a widget shows a range picker that does nothing, a chart that stays empty, or money that is a thousand times too large. Covers the descriptor contract, which flag turns on which control, and the four files a metric touches. For a whole new provider see `add-integration`; for a user's own one-off metric see `custom-metric`.
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
| `label`           | The name in the gallery and the configure pane's header.           |
| `methodology`     | Always shown, under Data. This is where "ours differs from theirs" |
| `granularities`   | Only read when there is a series. See the trap below.              |
| `keywords`        | Gallery search. Central ones are in `keywords.ts`.                 |

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

## Traps

**Money is integer minor units plus an ISO 4217 code.** Never a float, never
major units. A `unit: "currency"` metric returning `20.69` renders as 20 cents.

**`granularities` on a snapshot is dead metadata.** All 19 snapshot metrics
declare them and nothing reads them — `granularities.first` is sent on a
request whose window is ignored. Harmless, and misleading when you are reading
a manifest to work out what a metric does. Leave an existing one alone; do not
add them to a new snapshot.

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
