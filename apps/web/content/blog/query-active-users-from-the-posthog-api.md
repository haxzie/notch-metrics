---
title: "How to query active users from the PostHog API"
description: "HogQL through the query endpoint, why uniq is not a sum, and the de-duplication that makes weekly actives smaller than you expect."
date: 2026-10-11
author: Notch Metrics
tags: [posthog, analytics, api]
pillar: posthog-active-users-on-your-mac
faq:
  - question: How do I query active users in PostHog with the API?
    answer: >-
      POST to /api/projects/{id}/query/ with a HogQLQuery and SELECT
      uniq(person_id) over your time range. HogQL is SQL, so you get back the
      columns you named instead of a chart-shaped payload.
  - question: Why is my PostHog weekly active user count lower than the sum of daily counts?
    answer: >-
      Because uniq de-duplicates across the whole window. Somebody active on
      three days counts once. A weekly active count is strictly smaller than the
      sum of seven daily ones, and summing a daily series is the most common
      PostHog reporting bug.
  - question: Should I count person_id or distinct_id in PostHog?
    answer: >-
      person_id for users. It is PostHog's resolved person after identity
      merging, so the same human on a phone and a laptop is one person.
      distinct_id counts devices.
  - question: Why does my PostHog weekly chart disagree with the UI by a day?
    answer: >-
      ClickHouse's toStartOfWeek defaults to Sunday and PostHog's dashboards
      default to Monday. Pass 1 as the second argument, toStartOfWeek(timestamp,
      1), to start weeks on Monday.
  - question: Should I name my PostHog HogQL queries?
    answer: >-
      Yes. Pass a name alongside the query. PostHog surfaces query names in its
      usage views, so anybody looking at load on the project sees who is asking
      rather than an anonymous SELECT.
---

## Which PostHog endpoint answers "how many active users"?

The query endpoint, with HogQL. PostHog has an insights API and a trends API,
but both make you construct a filter object and then interpret an output
shape designed for a chart component.

HogQL is SQL. You write what you want and get back columns you named.

```bash
curl -s 'https://eu.posthog.com/api/projects/12345/query/' \
  -H 'Authorization: Bearer phx_...' \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "kind": "HogQLQuery",
      "query": "SELECT uniq(person_id) AS value FROM events WHERE timestamp >= toDateTime(1759276800) AND timestamp < toDateTime(1759881600)"
    }
  }'
```

The response carries a `results` array of rows, matching the columns you
selected. No shape to reverse-engineer.

## uniq, and why the number is smaller than you expected

`uniq(person_id)` de-duplicates across everything the query covers. Over a
week, somebody active on three days counts once.

That means a weekly active user count is **not** the sum of seven daily
counts, and it is not the average either. It is strictly smaller than the sum
and usually much smaller.

If you want a daily series alongside the de-duplicated total, that is two
queries, not one:

```sql
-- The series. Each day de-duplicated within itself.
SELECT toUnixTimestamp(toStartOfDay(timestamp)) AS bucket, uniq(person_id) AS value
FROM events
WHERE timestamp >= toDateTime({from}) AND timestamp < toDateTime({to})
GROUP BY bucket ORDER BY bucket

-- The headline. De-duplicated across the whole window.
SELECT uniq(person_id) AS value
FROM events
WHERE timestamp >= toDateTime({from}) AND timestamp < toDateTime({to})
```

Running only the first and summing it is the single most common PostHog
reporting bug, and it inflates the figure by however much your users come
back, which is exactly the thing you were trying to measure.

## person_id, not distinct_id

`distinct_id` is per device and per session identifier. `person_id` is
PostHog's resolved person after identity merging, so the same human on a
phone and a laptop is one person.

Counting `distinct_id` counts devices. Sometimes that is what you want. It is
almost never what somebody means by "active users".

## toStartOfWeek starts on Monday

ClickHouse's `toStartOfWeek` defaults to Sunday. PostHog's own dashboards
default to Monday. The two disagree by a day and the difference is invisible
until somebody compares a weekly chart against the UI.

```sql
toStartOfWeek(timestamp, 1)  -- 1 = Monday
```

## Timezone

HogQL evaluates in the project's timezone, which is what you want: it makes
your query agree with the PostHog UI. If you need a different one,
`toTimeZone(timestamp, 'Europe/London')` is explicit, and being explicit is
worth the extra characters in anything that will be read later.

## Name your queries

```json
{ "query": { "kind": "HogQLQuery", "query": "..." }, "name": "notch:active_users" }
```

PostHog surfaces query names in its own usage views. Anybody looking at who
is hammering their project sees a name rather than an anonymous `SELECT`,
which is the difference between a question and an incident.

## Or read it off the notch

Notch Metrics queries PostHog this way and reports
[active users](/sources/posthog/active-users) in the MacBook notch, with the
headline de-duplicated across the window and each bar de-duplicated within
its own day. The page says so rather than leaving you to discover it.

[New users](/sources/posthog/new-users),
[events](/sources/posthog/events),
[pageviews](/sources/posthog/pageviews) and
[sessions](/sources/posthog/sessions) sit beside it.
[Everything PostHog reports](/sources/posthog), or
[download Notch Metrics](/download).
