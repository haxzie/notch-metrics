# A widget format for Notch Metrics

**Status:** proposal, nothing built yet.

This describes a declarative format for defining a widget — what it shows,
where each piece goes, and where its data comes from — and the integration-side
data model that feeds it.

## What is actually limiting us today

A widget currently points at a pair: `(integrationId, metricId)`. `MetricId` is
a **closed enum of 34 ids** in `packages/schemas/src/ids.ts`, and every adapter
implements one function:

```ts
fetchMetric(ctx, credentials, request): Promise<RawSeries>
```

`RawSeries` is one shape for everything: a headline `value`, an optional
`previousValue`, and a flat array of `{ t, v }` points.

Three consequences, and only the first is obvious:

1. **An integration cannot expose anything the enum does not already name.**
   Adding "MRR by plan" or "top 5 pages" means editing a shared enum that every
   provider sees, then shipping it everywhere.
2. **Every widget looks the same.** `WidgetTile` hard-codes the arrangement:
   mark and app name, then a label, then a value, then maybe a sparkline. The
   only thing a widget chooses is which numbers land in those positions.
3. **Anything that is not one number over time is unrepresentable.** A
   breakdown, a list, a ratio of two sources, a status — none of them fit
   `RawSeries`, so none of them can exist.

So the request is right. But the two halves have very different costs and
should not be built together.

## The part of the brief I would push back on

> Where does the title go? The name, description, or any other element?

**I do not think we should build a layout language, and I think building one
would be the expensive mistake here.**

The reason is the canvas. A widget renders at 1x1, 2x1, 2x2 and 6x2 — and 1x1
is about 58pt square. At that size there is room for a mark, a short label and
a number. There is no meaningful arrangement to express. Grafana's and
Vega-Lite's grammars exist for a 1200px dashboard where the author genuinely
has layout decisions to make; at 58pt the renderer has to make them, because
almost every arrangement an author could write would simply not fit.

A layout language would also have to be interpreted by hand-written SwiftUI.
Every construct — stacks, spacers, alignment, overflow — becomes Swift we
maintain, and the failure mode is a widget that renders as a clipped mess on
someone's machine with no way for us to see it.

**The alternative: named slots.** A widget says _which_ slots it fills and with
what; the renderer owns where they go at each size. This is how WidgetKit and
Slack's Block Kit work in practice, and it has the property we need most —
**the same widget degrades across four sizes without the author writing four
layouts.**

That still gives you everything in the brief: the title, the name, the
description and any other element are each declared, named, and bound to data.
What it does not give you is freedom to put the title at the bottom right. I
think that is a feature at this size, and I would rather be told I am wrong now
than build the general thing and discover nobody can make a 1x1 that fits.

The data half of the brief I agree with completely, and it is where the value
is.

## Two artefacts, deliberately separate

Conflating "what data exists" with "how it is drawn" is the main error to
avoid. One is owned by the integration author and changes when a provider's API
changes; the other is owned by whoever designs a widget, including an agent
over MCP.

### 1. `DataSource` — what an integration exposes

Declared in TypeScript next to the adapter, exactly like manifests are now, so
`pnpm contracts` can emit its JSON Schema and the Swift structs stay honest.

```ts
export const mrrByPlan = defineSource({
  id: "stripe.mrr_by_plan",
  name: "MRR by plan",
  keywords: ["recurring", "revenue", "breakdown", "plans"],

  // What the widget may pass. Zod, so it validates on the way in and emits
  // JSON Schema on the way out.
  params: z.object({
    range: TimeRange.default("30d"),
    limit: z.number().int().min(1).max(20).default(5),
  }),

  // The shape of the answer. This is the contract a widget binds against.
  returns: Shape.breakdown({
    unit: "currency",
    rows: z.object({ key: z.string(), label: z.string(), value: z.number() }),
  }),

  cache: { ttlSeconds: 900 },

  async fetch(ctx, credentials, params) {
    /* … */
  },
});
```

Four return shapes, and I would resist adding a fifth without a real case:

| Shape       | Payload                         | For                          |
| ----------- | ------------------------------- | ---------------------------- |
| `scalar`    | `{ value, unit, currency? }`    | A number. Active subscribers |
| `series`    | `scalar` + `points[]` + `delta` | A number over time. Revenue  |
| `breakdown` | `{ rows: [{key,label,value}] }` | Top plans, top pages         |
| `status`    | `{ state, label, detail? }`     | Build passing, incidents     |

`MetricId` stops being a closed enum and becomes a namespaced string
(`stripe.mrr`). The existing 34 ids become sources with the same names, so
nothing breaks on day one.

### 2. `WidgetSpec` — how it is drawn

```json
{
  "schemaVersion": 1,
  "id": "stripe.mrr.with_trend",
  "appId": "stripe",
  "name": "Monthly recurring revenue",
  "description": "Your subscription book, normalised to a month.",
  "sizes": ["1x1", "2x1", "2x2", "6x2"],

  "data": {
    "primary": { "source": "stripe.mrr", "params": { "range": "30d" } }
  },

  "slots": {
    "source": { "kind": "appMark" },
    "label": { "kind": "text", "text": "{{ spec.name }}" },
    "value": { "kind": "number", "from": "{{ primary.value }}" },
    "delta": { "kind": "delta", "from": "{{ primary.delta.percent }}" },
    "chart": { "kind": "sparkline", "from": "{{ primary.points }}" }
  },

  "bySize": {
    "1x1": { "hide": ["chart", "delta", "source"] },
    "6x2": { "chart": { "kind": "bars" } }
  }
}
```

**Slots are a fixed vocabulary**: `source`, `label`, `value`, `delta`, `chart`,
`caption`, `rows`, `footnote`. The renderer knows where each goes at each size.
`bySize` can hide a slot or swap an element kind, and that is the whole of the
layout control.

**Bindings are accessors, not expressions.** `{{ primary.delta.percent }}` is a
path into a named data result, with a short list of pure formatters
(`| compact`, `| percent`, `| money`). Deliberately not an expression language:
the moment it can compute, it needs a sandbox, a fuel limit and a Swift
interpreter that agrees with the TypeScript one.

**A widget can name more than one source.** That is how a ratio or a
comparison becomes possible:

```json
"data": {
  "signups": { "source": "plausible.visitors" },
  "paid":    { "source": "stripe.new_subscribers" }
},
"slots": {
  "value": { "kind": "ratio", "numerator": "{{ paid.value }}", "denominator": "{{ signups.value }}" }
}
```

## How these become endpoints

The brief suggested "a lot of API endpoints". I would do the opposite: **one
generic endpoint, plus a discoverable catalogue.**

```
GET  /v1/sources                       the catalogue, with JSON Schema per source
POST /v1/data                          { connectionId, source, params } → payload
POST /v1/data/batch                    the hot path, index-aligned, partial success
```

A hand-written route per source would mean a Worker deploy for every new source
and a Mac release to call it. One generic route keeps the property this
codebase already works hard for: **a new source, and a new widget using it,
ship without an app release.** The catalogue is what makes it discoverable, and
it is generated from the same zod definitions, so it cannot drift from what
`/v1/data` will actually accept.

Three non-negotiables on that endpoint:

- **A widget names a `source` id, never a URL.** A spec that could name a URL
  is an SSRF primitive holding the user's provider credentials, and specs can
  come from an agent over MCP.
- **Params are validated against the declared zod schema server-side.** The
  catalogue is a convenience for clients, not the enforcement point.
- **The connection must belong to the caller**, answered 404 not 403, as
  everywhere else in `/v1`.

## What this costs

Worth being plain about, because it is not small.

- **A renderer in Swift that walks slots.** Bounded — eight slots, maybe ten
  element kinds — but it replaces `WidgetTile`'s fixed body, and the same
  interpreter has to exist in React for the website.
- **A new element kind still needs a Mac release.** New _widgets_ and new
  _sources_ ship freely; new _kinds_ do not. I think that is the right line,
  and it should be stated rather than discovered.
- **`MetricId` opening up weakens a real guard.** The closed enum is why an
  exhaustive `switch` in `registry.test.ts` can prove every declared metric is
  handled. The replacement is that a source owns its own fetch function, so the
  question stops being askable — but the migration has to not lose coverage.
- **Caching gets per-source TTLs** instead of one table of granularity rules.
  `metric_cache` keys on `<integrationId>:<metric>:<gran>:<rangeKey>`; it would
  key on a hash of `(connectionId, source, params)`.

## What I would build first

Not all of it. In order, each shippable on its own:

1. **`DataSource` and the generic `/v1/data` endpoint**, with the existing 34
   metrics re-declared as sources. No format change, no renderer change — the
   current widget keeps working, and the new plumbing is proven against real
   adapters. This is the part with all the value and none of the renderer risk.
2. **`WidgetSpec` with slots**, rendering the four existing tile shapes.
   Behaviour identical to today; the arrangement just comes from a spec.
3. **The shapes beyond `series`** — `breakdown`, `status` — and the element
   kinds that draw them. This is where new product appears.
4. **MCP authoring**, so an agent can write a spec. Last deliberately: the lint
   rules for a spec are much easier to write once specs exist.

Stopping after 1 would already be worth it.

## Rejected

- **Vega-Lite.** Right grammar, wrong canvas, and it would need a Vega
  interpreter in Swift.
- **Grafana panel JSON.** Shaped around a 12-column web dashboard with
  datasource plugins; the layout model does not survive a 58pt tile.
- **Adaptive Cards.** The closest fit, and genuinely tempting — it is a slot-ish
  card format with a real schema. Rejected because its vocabulary is sized for
  chat cards (images, actions, inputs, columns) and we would implement perhaps
  a tenth of it while still owing users the other nine tenths that the schema
  promises.
- **SwiftUI-shaped JSON** (`{"vstack": [...]}`). Trivially expressive, and the
  trap: it makes every layout decision the author's, including the ones they
  cannot test at four sizes on hardware they do not have.
