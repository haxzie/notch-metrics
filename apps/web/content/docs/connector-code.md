---
title: The code
description: Metrics are objects that carry their own fetch. One file, one export, no dispatch to write.
summary: createMetric, the context object, and what fetch returns.
section: apps
order: 3
date: 2026-10-26
---

`connector.mjs` has one default export. Each metric carries its own `fetch`,
so there is no dispatch to write.

```js
import { createApp, createMetric } from "@notchmetrics/core";

const downloads = createMetric({
  id: "downloads",
  label: "Downloads",
  unit: "count",
  series: { granularities: ["day"] },
  methodology: "Downloads reported by the registry for the window.",
  params: [{ key: "package", label: "Package", type: "string" }],

  async fetch(ctx, request) {
    const name = request.params.package ?? "react";
    const response = await ctx.http(
      `https://api.npmjs.org/downloads/range/${request.from}:${request.to}/${name}`,
    );
    if (!response.ok) throw new Error(`The registry returned ${response.status}.`);

    const body = await response.json();
    const points = body.downloads.map((day) => ({ t: day.day, v: day.downloads }));
    return { value: points.reduce((total, point) => total + point.v, 0), points };
  },
});

export default createApp({
  id: "npm-downloads",
  name: "npm downloads",
  description: "Download counts for a package on the npm registry.",
  allowedHosts: ["api.npmjs.org"],
  metrics: [downloads],
});
```

Everything about a metric sits in one object: what it is called, what it
means, what the widget asks for, and the code that answers it. Adding one is
adding an object to that array.

The import is types only. Nothing is loaded at run time, so a connector with
no `node_modules` beside it runs exactly the same.

## createMetric

| Field         | What it does                                                 |
| ------------- | ------------------------------------------------------------ |
| `id`          | Names the metric. Used to route a request, so it is stable.  |
| `label`       | What the widget gallery shows.                               |
| `shortLabel`  | What fits in a tile, twelve characters. Defaults to `label`. |
| `unit`        | `currency`, `count`, `ratio`, `duration` or `bytes`.         |
| `methodology` | How this number is derived, in one sentence. Required.       |
| `params`      | Fields the widget supplies, like a repository name.          |
| `fetch`       | Answers the metric for one window.                           |

### The kind

Set exactly one. It decides which shapes the widget offers and whether the
window means anything.

```js
scalar: true; // one number for now
series: {
  granularities: ["day"];
} // a number per bucket
total: {
  granularities: ["day"];
} // one number for the window
list: {
  limit: 6;
} // rows of categories
```

A `series` and a `total` compare against the previous window by default. Pass
`compare: false` where the API cannot answer that cheaply.

### Money

`unit: "currency"` takes an integer in minor units and an ISO 4217 code.
Never a float.

```js
return { value: 125_00, currency: "GBP" };
```

## The context

`fetch` and `verify` both receive `ctx`.

| Field             | What it is                                                |
| ----------------- | --------------------------------------------------------- |
| `ctx.credentials` | Only the keys your manifest declares, frozen              |
| `ctx.http`        | The only network access                                   |
| `ctx.timeRange`   | The window, as `from`, `to`, `granularity` and `timeZone` |
| `ctx.signal`      | Aborted when the run exceeds `timeoutMs`                  |
| `ctx.log`         | Lands in the run log, never on the tile                   |

`credentials` is filtered before your code runs, so a key the app never asked
for is not readable by it.

### Use ctx.http

```js
const response = await ctx.http("https://api.example.com/v1/users", {
  headers: { authorization: `Bearer ${ctx.credentials.api_key}` },
});
```

A bare `fetch` bypasses the host allowlist, the https requirement, the
redirect re-check and the 4 MB cap. Use `ctx.http`.

It returns `ok`, `status`, `headers`, `json()` and `text()`.

## The request

| Field                                  | What it is                                              |
| -------------------------------------- | ------------------------------------------------------- |
| `request.params`                       | Whatever the widget supplied for your declared `params` |
| `request.from`, `request.to`           | The window, as ISO timestamps                           |
| `request.range`, `request.granularity` | The window as the user chose it                         |
| `request.comparePrevious`              | Whether the previous window is wanted                   |
| `request.id`                           | Which widget asked. Opaque, and echoed back             |

`request.id` is what keeps two tiles on one metric apart. A tile for `react`
and a tile for `vue` are identical in every other field.

## What fetch returns

`value` is required. Everything else is optional.

| Field           | For                                         |
| --------------- | ------------------------------------------- |
| `previousValue` | The delta against the previous equal window |
| `points`        | A series, as `{ t, v }`                     |
| `items`         | Rows, for a list metric                     |
| `currency`      | An ISO 4217 code, for a currency metric     |
| `note`          | One line the tile shows under the figure    |

## verify

Optional. An app against a public API has nothing to prove.

Where there is a credential, `verify` runs before the app is usable.

```js
export default createApp({
  // the app's own fields, then:
  async verify(ctx) {
    const response = await ctx.http("https://api.example.com/v1/account", {
      headers: { authorization: `Bearer ${ctx.credentials.api_key}` },
    });
    if (!response.ok) throw new Error(`The API key was rejected (${response.status}).`);

    const account = await response.json();
    return { accountLabel: account.name, currency: account.currency };
  },
  metrics: [downloads],
});
```

Throw to reject. A key that does not work must not become an app that quietly
shows nothing.

Return `unavailableMetrics` to name the numbers this credential cannot reach.
A read only token that sees usage but not billing says so once, and those
widgets explain themselves.

## Errors

Throw with a sentence somebody can act on. The message reaches the tile, so
`The API returned 429.` is useful and `undefined is not an object` is not.

One metric that throws does not affect the others. A run that passes
`timeoutMs` is killed, and every metric in that run shares the budget.

## The older shape

A connector that exports `verify` and `fetchMetric` as named functions still
runs. That shape declared its metrics in a hand-written manifest and dispatched on
`request.metric` inside one function.

Nothing forces a rewrite. New connectors should use `createApp`,
because an id spelled two ways is a class of bug the newer shape cannot have.
