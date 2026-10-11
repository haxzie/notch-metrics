---
title: "How to pull clicks and impressions from the Search Console API"
description: "searchAnalytics.query, the site URL encoding that trips everyone up, and the row limits that make totals disagree with breakdowns."
date: 2026-10-11
author: Notch Metrics
tags: [google-search-console, seo, api]
pillar: search-console-clicks-in-your-notch
faq:
  - question: What is the Search Console API endpoint for clicks and impressions?
    answer: >-
      POST to /webmasters/v3/sites/{siteUrl}/searchAnalytics/query. Every row
      returns all four metrics, so there is no metric list to specify: clicks,
      impressions, ctr and position are always present.
  - question: How do I encode the site URL in the Search Console API path?
    answer: >-
      With encodeURIComponent, exactly as sites.list returns it. A domain
      property becomes sc-domain%3Aexample.com and a URL-prefix property keeps
      its trailing slash. Dropping the slash returns a 403 that reads like a
      permissions problem.
  - question: Why does my Search Console query breakdown not add up to the total?
    answer: >-
      Two reasons. rowLimit caps rows at 25,000, and Google withholds queries
      issued by very few people for privacy at any row limit. Ask without
      dimensions for the true total.
  - question: Can I average Search Console position across rows?
    answer: >-
      No. Each row's position is already averaged over that row's impressions,
      so averaging rows weights a query with ten impressions equally with one
      that had ten thousand. Ask for the undimensioned row instead.
  - question: Which timezone does Search Console use for daily data?
    answer: >-
      Pacific Time, regardless of where you or your users are. A daily figure
      compared against a UTC analytics series will disagree at the edges for
      every site outside that zone.
---

## The endpoint

One POST, and everything comes from it.

```bash
curl -s -X POST \
  'https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "startDate": "2026-10-01",
    "endDate": "2026-10-07",
    "dimensions": ["date"]
  }'
```

Every row comes back with all four metrics, so there is no metric list to
specify: `clicks`, `impressions`, `ctr` and `position` are always present.

## The site URL in the path

This is where most first attempts fail. The property identifier goes in the
URL path and it must be encoded.

| Property type | Identifier              | Encoded                        |
| ------------- | ----------------------- | ------------------------------ |
| Domain        | `sc-domain:example.com` | `sc-domain%3Aexample.com`      |
| URL prefix    | `https://example.com/`  | `https%3A%2F%2Fexample.com%2F` |

A URL-prefix property keeps its trailing slash, and dropping it returns a 403
that reads like a permissions problem rather than a not-found. Use
`encodeURIComponent` and copy the identifier exactly as the Search Console
API's site list returns it.

## Dimensions change what a row is

| `dimensions`        | One row per                     |
| ------------------- | ------------------------------- |
| `[]`                | The whole window, one row total |
| `["date"]`          | Day                             |
| `["query"]`         | Search term                     |
| `["page"]`          | URL                             |
| `["query", "page"]` | Combination                     |

Omitting dimensions entirely is the right call for a headline figure. It
returns a single row with the window's totals and no row limit to worry
about.

## Why your breakdown does not add up to your total

Two separate reasons, and both surprise people.

**Row limits.** `rowLimit` defaults to 1,000 and maxes at 25,000. A site with
more queries than that returns the top rows only, so summing them undercounts.

**Anonymised queries.** Google withholds queries issued by very few people,
for privacy. Those clicks exist in the totals and appear in no query
breakdown, at any row limit. On a long-tail site the withheld portion can be
a third of your traffic.

So a query-dimension sum is always less than or equal to the undimensioned
total, and the gap is not a bug to chase. Ask without dimensions when you
want the true total.

## CTR and position are computed, not summed

`ctr` is clicks over impressions **for that row**, and `position` is the
average position over that row's impressions.

Averaging the `position` values across rows is wrong: it weights a query with
ten impressions equally with one that had ten thousand. If you need an
overall position, ask for the undimensioned row and let Google compute it.

## The lag

Data settles over two to three days. An `endDate` of today returns a partial
figure that will grow.

For a stable series, end your window two or three days back. For a chart that
includes today, expect the last points to rise on every refresh, and say so
in the interface rather than letting somebody read it as a decline.

## Dates are property timezone, and that is Pacific

Search Console buckets by day in Pacific Time regardless of where you or your
users are. A daily figure compared against a UTC analytics series will
disagree at the edges for every site outside that zone.

## Auth

OAuth with `https://www.googleapis.com/auth/webmasters.readonly`, or a
service account granted access to the property. Use `sites.list` first to get
the exact identifier strings rather than constructing them.

## In the notch

Notch Metrics calls this endpoint and reports
[clicks](/sources/google-search-console/clicks),
[impressions](/sources/google-search-console/impressions),
[CTR](/sources/google-search-console/ctr) and
[average position](/sources/google-search-console/average-position) in the
MacBook notch, daily, weekly or monthly.

The two-to-three-day lag is stated on each page rather than hidden in a
drooping chart. [Everything Search Console reports](/sources/google-search-console),
or [download Notch Metrics](/download).
