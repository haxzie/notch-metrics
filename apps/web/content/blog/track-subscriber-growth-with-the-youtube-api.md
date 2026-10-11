---
title: "How to track subscriber growth with the YouTube API"
description: "The total is rounded and gross gains are not net. Which API returns which, and how to build a subscriber series that is not misleading."
date: 2026-10-11
author: Notch Metrics
tags: [youtube, subscribers, api]
pillar: youtube-views-and-revenue-on-your-mac
faq:
  - question: Why is the YouTube subscriber count rounded?
    answer: >-
      YouTube rounds counts above a thousand to three significant figures,
      publicly and in the Data API, so 12,345 reads as 12,300. The rounding gets
      coarser as a channel grows.
  - question: Can I build a subscriber growth chart by polling subscriberCount?
    answer: >-
      No. Differencing a rounded total produces a staircase, with flat runs and
      jumps that correspond to the rounding boundary rather than to anything
      that happened. Use subscribersGained and subscribersLost from the
      Analytics API instead.
  - question: Is subscribersGained net or gross?
    answer: >-
      Gross. YouTube reports subscribersGained and subscribersLost separately
      and does not net them, so a channel can gain two thousand and lose five
      hundred in the same week. Net is gained minus lost.
  - question: How do I find out where my YouTube subscribers came from?
    answer: >-
      Query subscribersGained with the insightTrafficSourceType dimension. It
      tells you whether they came from search, suggested videos, a channel page
      or an external link, which usually changes what to do next more than the
      total does.
  - question: Does a YouTube subscriber mean somebody watches?
    answer: >-
      Not necessarily. Subscribing costs one click and implies nothing about
      watching, and a channel's subscriber count and returning-viewer count can
      move in opposite directions for a long time. Watch time predicts future
      views better.
---

## Two numbers, two APIs

The current total and the change over a window come from different places.

**The total** is on the Data API's channel resource:

```bash
curl -s 'https://www.googleapis.com/youtube/v3/channels?part=statistics&mine=true' \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

`statistics.subscriberCount`, as a string.

**The change** is on the Analytics API:

```bash
curl -s -G 'https://youtubeanalytics.googleapis.com/v2/reports' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode 'ids=channel==MINE' \
  --data-urlencode 'startDate=2026-10-01' \
  --data-urlencode 'endDate=2026-10-07' \
  --data-urlencode 'metrics=subscribersGained,subscribersLost' \
  --data-urlencode 'dimensions=day'
```

## The total is rounded

This is the important one. Above a thousand subscribers YouTube rounds the
count to three significant figures, publicly and in the Data API. 12,345
reads as 12,300.

The rounding gets coarser as the channel grows, so a large channel can gain
hundreds of subscribers a day and report the same number for several days
before stepping.

Consequences:

**Do not build a growth series from the total.** Polling `subscriberCount`
daily and differencing it produces a staircase, with long flat runs and sudden
jumps that correspond to the rounding boundary rather than to anything that
happened.

**Do not compute a daily gain from it.** The difference between two rounded
numbers has an error of up to the rounding increment, which on a large channel
is larger than a normal day's gain.

The exact figures are in Analytics. Use them.

## Gained is gross, not net

`subscribersGained` counts people who subscribed. `subscribersLost` counts
people who left. YouTube reports them separately and does not net them.

A channel can gain two thousand and lose five hundred in the same week. A
"new subscribers" figure that shows two thousand is correct and is not
growth.

```js
const net = gained - lost;
```

Net is the number that moves your total. Gross is the number that tells you
whether your content is finding people, which is a different and also useful
question. Report whichever you mean and label it.

## Where subscriptions come from

Add the dimension and you get the surface:

```
dimensions=subscribedStatus,day
```

Or, more usefully:

```
dimensions=insightTrafficSourceType
metrics=subscribersGained
```

That tells you whether your subscribers came from search, from suggested
videos, from a channel page or from an external link. The answer usually
changes what you would do next far more than the total does.

## The lag

Subscriber metrics settle like everything else in Analytics, over a day or
two, and days are Pacific Time. A spike that looks like it happened on
Tuesday in London may be Monday in the data.

## A subscriber is not a viewer

Worth stating because the total is the number everybody optimises for.
Subscribing costs one click and implies nothing about watching. A channel's
subscriber count and its returning-viewer count can move in opposite
directions for a long time.

If you want the number that predicts future views, it is
[watch time](/sources/youtube/watch-time) and returning viewers, not this
one.

## In the notch

Notch Metrics reports
[YouTube subscribers](/sources/youtube/subscribers) as the current total
without a sparkline, because a chart of a rounded series draws steps that
look like stalled growth. The change against the previous window comes from
Analytics and is exact, so the arrow is right even where the total is
rounded.

[New subscribers](/sources/youtube/new-subscribers) is the gross gain in the
window, and the page says gross rather than letting you assume net.
[Everything YouTube reports](/sources/youtube), or
[download Notch Metrics](/download).
