---
title: "How to get views and watch time from the YouTube Analytics API"
description: "The reports.query endpoint, the ids parameter nobody guesses correctly, and the Pacific timezone that shifts every daily figure."
date: 2026-10-11
author: Notch Metrics
tags: [youtube, analytics, api]
pillar: youtube-views-and-revenue-on-your-mac
faq:
  - question: Which YouTube API returns views over a date range?
    answer: >-
      The YouTube Analytics API v2, at
      youtubeanalytics.googleapis.com/v2/reports. The Data API v3 answers
      channel metadata and the current subscriber count, not windowed metrics.
  - question: What is the ids parameter in the YouTube Analytics API?
    answer: >-
      A filter using two equals signs, such as ids=channel==MINE or
      ids=channel==UC... for a specific channel. A single equals sign returns a
      400 that does not say which parameter is wrong.
  - question: Which timezone does the YouTube Analytics API use?
    answer: >-
      America/Los_Angeles, and it is not configurable. A view at 02:00 in London
      is 18:00 Pacific the previous day, so a daily series disagrees with a UTC
      analytics tool at every boundary.
  - question: What unit is YouTube watch time in?
    answer: >-
      Minutes. The metric is estimatedMinutesWatched. Divide by 60 for hours,
      which is the unit any channel of size needs because a minute figure is too
      long to read at a glance.
  - question: Why do my YouTube view counts go down?
    answer: >-
      Because YouTube discards automated and repeated playback before
      publishing, and that validation lags. Unlike Search Console, the newest
      figures read high and settle downwards.
---

## Two APIs, and you need the right one

YouTube has a Data API and an Analytics API, and they answer different
questions.

| API              | Good for                                                      |
| ---------------- | ------------------------------------------------------------- |
| Data API v3      | Channel metadata, the current subscriber count, video details |
| Analytics API v2 | Views, watch time, revenue, anything over a window            |

For "how many views last week", it is Analytics.

```bash
curl -s -G 'https://youtubeanalytics.googleapis.com/v2/reports' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode 'ids=channel==MINE' \
  --data-urlencode 'startDate=2026-10-01' \
  --data-urlencode 'endDate=2026-10-07' \
  --data-urlencode 'metrics=views,estimatedMinutesWatched' \
  --data-urlencode 'dimensions=day'
```

## The ids parameter

`ids=channel==MINE`. Two equals signs, and that is not a typo.

It is the API's own filter syntax, and `channel==UC...` works for a specific
channel you have access to. `ids=channel=MINE` with one equals returns a 400
that does not explain which parameter is wrong.

For a content owner you use `contentOwner==OWNER_ID` instead, which is a
different grant entirely.

## The response is rows and column headers

```json
{
  "columnHeaders": [
    { "name": "day", "columnType": "DIMENSION", "dataType": "STRING" },
    { "name": "views", "columnType": "METRIC", "dataType": "INTEGER" },
    { "name": "estimatedMinutesWatched", "columnType": "METRIC", "dataType": "INTEGER" }
  ],
  "rows": [["2026-10-01", 4210, 18340]]
}
```

Rows are arrays, positional, matching `columnHeaders`. Build an index from
the headers rather than from your request:

```js
const index = Object.fromEntries(body.columnHeaders.map((h, i) => [h.name, i]));
const views = row[index.views];
```

Using the headers rather than your own metrics string is the safer of the
two, because the API can reorder and because a metric it silently dropped
shows up as a missing key rather than as a shifted column.

## Everything is Pacific Time

`day` buckets are `America/Los_Angeles`. Not UTC, not yours, and not
configurable.

A view at 21:00 in London is 13:00 Pacific the same day. A view at 02:00 in
London is 18:00 Pacific the **previous** day. So a daily series compared
against a UTC analytics tool disagrees at every boundary, and the
disagreement is largest for channels whose audience is furthest from the
Pacific coast.

## Watch time is minutes

`estimatedMinutesWatched` is exactly what it says. Divide by 60 for hours,
which is the unit any channel of size needs, because a minute figure is too
long to read at a glance.

Watch time is the metric YouTube's recommendation systems weight most, which
makes it the more useful of the two. Views count arrivals; watch time counts
attention.

## Views settle downwards

YouTube discards automated and repeated playback before publishing, and that
validation lags. The newest day or two can fall after the fact.

Unlike Search Console, the drop here is a correction rather than an arrival,
so the newest figures read **high** and settle **down**. Worth knowing which
direction before you read a change.

## Scopes

`https://www.googleapis.com/auth/youtube.readonly` for views and watch time.
Revenue needs
`https://www.googleapis.com/auth/yt-analytics-monetary.readonly` as well, and
asking for it when you do not need it makes the consent screen more alarming
than it has to be.

## In the notch

Notch Metrics calls `reports.query` and shows
[YouTube views](/sources/youtube/views),
[watch time](/sources/youtube/watch-time) in hours, and
[average view duration](/sources/youtube/average-view-duration) in the
MacBook notch, daily, weekly or monthly, bucketed in Pacific Time as YouTube
reports them.

[Everything YouTube reports](/sources/youtube), or
[download Notch Metrics](/download).
