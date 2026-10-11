---
title: "How to get active users from the GA4 Data API"
description: "runReport, the metric names that are not what they were in Universal Analytics, and the de-duplication that makes totals smaller than rows."
date: 2026-10-11
author: Notch Metrics
tags: [google-analytics, ga4, api]
pillar: ga4-visitors-in-your-notch
faq:
  - question: What is the GA4 Data API endpoint for a report?
    answer: >-
      POST to https://analyticsdata.googleapis.com/v1beta/properties/{propertyId
      }:runReport. The property id is the numeric one, not the measurement id
      beginning with G- from your tracking snippet.
  - question: What is the GA4 metric name for pageviews?
    answer: >-
      screenPageViews. There is no pageViews metric in GA4: the name folds app
      screens and web pages into one metric because GA4 treats both as the same
      kind of thing.
  - question: Can I sum daily GA4 active users to get a weekly figure?
    answer: >-
      No. Each daily row is de-duplicated within its own day, so a person active
      on three days appears in three rows. Ask for metricAggregations TOTAL, or
      run the query without a date dimension, to get the de-duplicated window
      figure.
  - question: Why are GA4 Data API numbers returned as strings?
    answer: >-
      Google serialises metric values as strings, including integers. Convert
      before arithmetic, or summing them concatenates. The failure is loud
      rather than subtle, which helps.
  - question: Why does my GA4 breakdown add up to less than the total?
    answer: >-
      Thresholding. GA4 withholds rows with very few users to protect identity,
      especially where demographics are involved. A missing row is not a zero.
---

## The endpoint

GA4 reporting is one POST to the Data API.

```bash
curl -s -X POST \
  'https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "dateRanges": [{ "startDate": "2026-10-01", "endDate": "2026-10-07" }],
    "dimensions": [{ "name": "date" }],
    "metrics": [{ "name": "activeUsers" }]
  }'
```

The property id is numeric, and it goes in the URL path. It is not the
measurement id beginning with `G-`, which is the one in your tracking
snippet. Mixing them up returns a 403 that reads like a permissions problem.

## The metric names changed

If you are porting anything from Universal Analytics, the vocabulary moved.

| What you want | UA             | GA4               |
| ------------- | -------------- | ----------------- |
| Users         | `ga:users`     | `activeUsers`     |
| New users     | `ga:newUsers`  | `newUsers`        |
| Sessions      | `ga:sessions`  | `sessions`        |
| Pageviews     | `ga:pageviews` | `screenPageViews` |

`screenPageViews` is the one that catches people. There is no `pageViews` in
GA4: the name folds app screens and web pages into one metric, because GA4
treats both as the same kind of thing.

A metric name GA4 does not know returns a 400 naming the field, which is at
least a clear failure.

## The response, and where the total is

```json
{
  "dimensionHeaders": [{ "name": "date" }],
  "metricHeaders": [{ "name": "activeUsers", "type": "TYPE_INTEGER" }],
  "rows": [{ "dimensionValues": [{ "value": "20261001" }], "metricValues": [{ "value": "120" }] }],
  "rowCount": 7
}
```

Values are **strings**, including integers. `"120"`, not `120`. Summing them
without converting concatenates, which produces an absurd number rather than
a subtly wrong one, so at least it fails loudly.

Dates come back as `YYYYMMDD` with no separators.

## Do not sum the rows

This is the central thing. Summing `activeUsers` across seven daily rows does
not give you weekly active users. Each row is de-duplicated within its own
day, and a person active on three days appears in three rows.

For the de-duplicated total, ask for it:

```json
{
  "dateRanges": [{ "startDate": "2026-10-01", "endDate": "2026-10-07" }],
  "metrics": [{ "name": "activeUsers" }],
  "metricAggregations": ["TOTAL"]
}
```

The result arrives in `totals`, separate from `rows`, and it is correctly
de-duplicated across the window. Or run the query with no `date` dimension at
all, which gives you a single row that means the same thing.

Either way, the headline and the chart are two requests or one request with
aggregations, and they will not match. That is right.

## Data is sampled and thresholded

Two caveats worth carrying with any GA4 figure.

**Sampling.** Large properties with complex queries get sampled results, and
the response says so. Check for it rather than assuming.

**Thresholding.** GA4 withholds rows with very few users to protect identity,
especially when demographics are involved. So a breakdown can add up to less
than its total, and a missing row is not a zero.

## Authentication

OAuth with `https://www.googleapis.com/auth/analytics.readonly`, or a service
account added as a viewer on the property. The service account route is
better for anything unattended, because an OAuth refresh token is one
revocation away from a silent outage.

## Or read it off the notch

Notch Metrics calls `runReport` and shows
[GA4 active users](/sources/google-analytics/active-users),
[new users](/sources/google-analytics/new-users),
[sessions](/sources/google-analytics/sessions) and
[page views](/sources/google-analytics/pageviews) in the MacBook notch, with
the headline de-duplicated over the window and the chart per day, which the
page explains rather than leaving you to notice.

[Everything Google Analytics reports](/sources/google-analytics), or
[download Notch Metrics](/download).
