---
title: "How to use the Plausible Stats API v2"
description: "One POST endpoint for every query. The v2 shape, how metrics and dimensions fit together, and what changed from the v1 GET endpoints."
date: 2026-10-11
author: Notch Metrics
tags: [plausible, analytics, api]
pillar: plausible-visitors-in-your-notch
faq:
  - question: What is the Plausible Stats API v2 endpoint?
    answer: >-
      A single POST to https://plausible.io/api/v2/query taking a JSON body with
      site_id, metrics, date_range and optional dimensions. v1 used separate GET
      endpoints for aggregate, timeseries and breakdown.
  - question: How do I read the Plausible v2 response?
    answer: >-
      Each result row has a metrics array that is positional, matching the order
      you requested metrics in, and a dimensions array. Build a lookup from your
      own request rather than indexing by a hardcoded number, or reordering the
      request silently breaks every reader.
  - question: What format is Plausible site_id?
    answer: >-
      The domain as it appears in your Plausible site list, such as example.com,
      with no scheme and no trailing slash. It is not a UUID or a numeric id.
  - question: Can I get a Plausible aggregate figure rather than a series?
    answer: >-
      Yes. Omit dimensions entirely and the response is a single row covering
      the whole date range. Adding time:day to dimensions turns it into a daily
      series.
  - question: Is realtime visitors part of the Plausible v2 API?
    answer: >-
      No. Current visitors remains a v1 GET at /api/v1/stats/realtime/visitors,
      and it returns a bare integer rather than a JSON object.
---

## What is different about Stats API v2?

v1 was a family of GET endpoints: one for aggregate, one for timeseries, one
for breakdowns, each with its own parameters. v2 is a single POST endpoint
that takes a query object.

```bash
curl -s https://plausible.io/api/v2/query \
  -H 'Authorization: Bearer <api key>' \
  -H 'Content-Type: application/json' \
  -d '{
    "site_id": "example.com",
    "metrics": ["visitors", "pageviews", "bounce_rate"],
    "date_range": ["2026-10-01", "2026-10-07"],
    "dimensions": ["time:day"]
  }'
```

One request, three metrics, bucketed daily. Under v1 that was three requests
and three response shapes.

## The response is rows, not objects

```json
{
  "results": [
    { "metrics": [120, 340, 0.41], "dimensions": ["2026-10-01"] },
    { "metrics": [98, 250, 0.38], "dimensions": ["2026-10-02"] }
  ]
}
```

`metrics` is positional: it matches the order you asked for them in. There
are no keys.

That is efficient and it is a trap. Reorder your request and every reader
downstream silently reads the wrong column. Build a lookup from your own
request rather than indexing by a hardcoded number:

```js
const index = Object.fromEntries(query.metrics.map((m, i) => [m, i]));
const visitors = row.metrics[index.visitors];
```

## site_id is the domain

Not a UUID, not a numeric id. `example.com`, exactly as it appears in your
Plausible site list, without a scheme and without a trailing slash.

A site id that does not match returns an error rather than empty data, which
is at least a clear failure.

## Dimensions do the work

`dimensions` is where v2 gets its range.

| Dimension                             | What you get      |
| ------------------------------------- | ----------------- |
| `time:day`, `time:hour`, `time:month` | A series          |
| `visit:source`, `visit:referrer`      | Traffic sources   |
| `event:page`                          | Top pages         |
| `visit:country`                       | Geography         |
| `event:props:<name>`                  | A custom property |

Omit `dimensions` entirely and you get one row: the aggregate over the whole
range. That is the equivalent of the old aggregate endpoint and it is the
right call when you want a headline figure rather than a chart.

## date_range accepts shorthand

Either an explicit pair of ISO dates, or a shorthand string:

```json
"date_range": "7d"
```

`"day"`, `"7d"`, `"30d"`, `"month"`, `"6mo"`, `"12mo"` and `"all"` are
available. The shorthand is resolved in the site's timezone, which saves you
computing the boundaries yourself and getting them wrong near midnight.

## Realtime is still its own thing

Current visitors is not a v2 query. It remains:

```bash
curl -s 'https://plausible.io/api/v1/stats/realtime/visitors?site_id=example.com' \
  -H 'Authorization: Bearer <api key>'
```

A bare integer, no JSON wrapper.

## Rate limits and keys

API keys are per user rather than per site, and one key reads every site you
have access to. The limit is generous for dashboards and not for a tight
polling loop. Cache anything you refresh more than once a minute.

## Or read it off the notch

Notch Metrics queries the v2 endpoint and reports
[unique visitors](/sources/plausible/visitors),
[pageviews](/sources/plausible/pageviews),
[sessions](/sources/plausible/sessions) and
[bounce rate](/sources/plausible/bounce-rate) in the MacBook notch, bucketed
in your Plausible site's own timezone.

One connection, a key that never reaches your Mac.
[Everything Plausible reports](/sources/plausible), or
[download Notch Metrics](/download).
