---
title: "How to pull sessions and page views from GA4"
description: "Two metrics, one request, and the engaged-session definition that makes GA4 numbers disagree with every tool you had before."
date: 2026-10-11
author: Notch Metrics
tags: [google-analytics, ga4, api]
pillar: ga4-visitors-in-your-notch
faq:
  - question: What counts as a session in GA4?
    answer: >-
      A session starts with a session_start event and ends after thirty minutes
      of inactivity, or at midnight in the property's timezone. The midnight
      rule means a visit spanning midnight is two sessions, unlike most other
      tools.
  - question: What is the difference between sessions and engagedSessions in GA4?
    answer: >-
      An engaged session lasted at least ten seconds, had two or more pageviews,
      or included a conversion. engagedSessions excludes the accidental arrivals
      that a raw session count treats as visits, which makes it the more honest
      traffic figure.
  - question: Is GA4 bounce rate the same as Universal Analytics bounce rate?
    answer: >-
      No. GA4 bounce rate is one minus engagement rate. Universal Analytics
      counted single-pageview sessions. The two are not comparable and should
      not share an axis across a migration date.
  - question: Can I sum daily GA4 page views?
    answer: >-
      Yes. Unlike active users, screenPageViews is not de-duplicated, so daily
      rows add up correctly. The two metrics behave differently under addition
      even in the same response.
  - question: Should I use pagePath or pagePathPlusQueryString in GA4?
    answer: >-
      pagePath for a top pages ranking. pagePathPlusQueryString keeps the query
      string, which fragments one page across every UTM variant.
---

## One request, both metrics

The Data API takes a list, so sessions and page views come back together.

```json
{
  "dateRanges": [{ "startDate": "2026-10-01", "endDate": "2026-10-07" }],
  "dimensions": [{ "name": "date" }],
  "metrics": [{ "name": "sessions" }, { "name": "screenPageViews" }]
}
```

`metricValues` in each row is positional, matching the order you asked. Build
a lookup from your own request rather than indexing with a literal, because
reordering the metrics array silently reassigns every reader downstream.

```js
const index = Object.fromEntries(query.metrics.map((m, i) => [m.name, i]));
const sessions = Number(row.metricValues[index.sessions].value);
```

## What a GA4 session is

A session starts with a `session_start` event and ends after thirty minutes
of inactivity, or at midnight in the property's timezone.

That midnight rule is the one that differs from most tools. A visit spanning
midnight is **two sessions** in GA4, not one. On a consumer product with
evening traffic this inflates session counts relative to anything that stitches
across the boundary.

The thirty-minute timeout is configurable per property. If somebody changed
it, your historical series has a step in it that is not behaviour.

## engagedSessions is the one people actually want

GA4 added a definition that Universal Analytics did not have.

| Metric            | What it counts                                    |
| ----------------- | ------------------------------------------------- |
| `sessions`        | Every session                                     |
| `engagedSessions` | Lasted 10s+, or had 2+ pageviews, or a conversion |
| `engagementRate`  | Engaged over total                                |
| `bounceRate`      | 1 minus engagement rate                           |

GA4's bounce rate is therefore the inverse of engagement, not Universal
Analytics' single-pageview definition. The two numbers are not comparable and
a chart that puts them on one axis across the migration date is wrong.

For most purposes `engagedSessions` is the more honest traffic figure,
because it excludes the accidental arrivals that a raw session count treats
as visits.

## screenPageViews counts repeats

Unlike users, page views are not de-duplicated. A visitor loading the same
page five times is five page views, which is what a page view is.

That also means summing daily rows **is** correct for page views, unlike
active users. The two metrics in the same response behave differently under
addition, which is a genuinely confusing property of GA4 reporting and worth
a comment in whatever code does the summing.

## Pages, not just totals

Swap the dimension to get the breakdown:

```json
{
  "dimensions": [{ "name": "pagePath" }],
  "metrics": [{ "name": "screenPageViews" }],
  "orderBys": [{ "metric": { "metricName": "screenPageViews" }, "desc": true }],
  "limit": 20
}
```

`pagePath` excludes the host and the query string. `pagePathPlusQueryString`
keeps the query, which fragments your top pages across every UTM variant and
is almost never what you want in a ranking.

## Timezone

Every date dimension is bucketed in the property's reporting timezone, which
is set in GA4 and not derived from your request. A change to it does not
restate history, so a property whose timezone was corrected has a seam.

## In the notch

Notch Metrics reports
[GA4 sessions](/sources/google-analytics/sessions) and
[page views](/sources/google-analytics/pageviews) in the MacBook notch,
daily, weekly or monthly, with a sparkline and a comparison against the
previous window.

Place them beside
[active users](/sources/google-analytics/active-users) and the three describe
the visit rather than just counting it.
[Everything Google Analytics reports](/sources/google-analytics), or
[download Notch Metrics](/download).
