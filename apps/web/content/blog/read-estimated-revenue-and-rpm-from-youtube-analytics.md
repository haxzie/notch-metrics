---
title: "How to read estimated revenue and RPM from YouTube Analytics"
description: "RPM is not CPM, and estimated revenue is not ad revenue. The four money metrics, what each includes, and the scope you need."
date: 2026-10-11
author: Notch Metrics
tags: [youtube, revenue, api]
pillar: youtube-views-and-revenue-on-your-mac
faq:
  - question: What is the difference between RPM and CPM on YouTube?
    answer: >-
      RPM is your revenue after YouTube's share, divided by every view. CPM is
      what advertisers paid, before YouTube's share, divided by monetised ad
      impressions. CPM is always much higher, on every channel, and the gap is
      two different ratios rather than a problem.
  - question: Does the YouTube Analytics API return RPM?
    answer: >-
      No. Compute it as revenue divided by views times a thousand, over the
      whole window. Averaging daily RPM values weights a quiet day with one
      high-value view equally with a day of ten thousand views.
  - question: What is the difference between YouTube estimated revenue and estimated ad revenue?
    answer: >-
      Estimated revenue includes advertising, channel memberships, Super Chat,
      Super Thanks and Premium watch-time revenue. Ad revenue is the advertising
      part alone. The gap is the part of the channel that is not advertising.
  - question: Which scope do I need for YouTube revenue data?
    answer: >-
      https://www.googleapis.com/auth/yt-analytics-monetary.readonly, in
      addition to the read-only YouTube scope. Asking for it when you do not
      need revenue makes the consent screen more alarming than it has to be.
  - question: Why does the YouTube API return an error instead of zero revenue?
    answer: >-
      Because the channel is outside the YouTube Partner Programme. Zero revenue
      and no revenue programme are different states, and reporting the second as
      the first would be a lie with a number attached.
---

## The four money metrics

YouTube Analytics reports several revenue figures and they are routinely
confused with each other.

| Metric               | What it includes                                                |
| -------------------- | --------------------------------------------------------------- |
| `estimatedRevenue`   | Everything: ads, memberships, Super Chat, Super Thanks, Premium |
| `estimatedAdRevenue` | Advertising only                                                |
| `grossRevenue`       | Before YouTube's share                                          |
| `cpm`                | Cost per thousand ad impressions                                |

Plus RPM, which is not in that list because the API does not return it
directly. More on that below.

```bash
curl -s -G 'https://youtubeanalytics.googleapis.com/v2/reports' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode 'ids=channel==MINE' \
  --data-urlencode 'startDate=2026-09-01' \
  --data-urlencode 'endDate=2026-09-30' \
  --data-urlencode 'metrics=estimatedRevenue,estimatedAdRevenue,views' \
  --data-urlencode 'dimensions=day'
```

## Estimated revenue against ad revenue

The gap between these two is the part of your channel that is not
advertising. For a creator with memberships it can be most of the income.

Watching only the total hides the shape. A channel whose estimated revenue
holds steady while ad revenue falls is being carried by its members, which is
a more durable business and a completely different one from the total's
implication.

Track both.

## RPM is computed, not returned

RPM is revenue per thousand views: total revenue over total views, with every
view counted.

```js
const rpm = (estimatedRevenue / views) * 1000;
```

Compute it over the **whole window**, not by averaging daily rates. A quiet
day with one high-value view produces an enormous daily RPM and should
contribute almost nothing to the figure. Averaging the points weights it
equally with a day of ten thousand views, and the result is a number that
jumps around for no reason.

## RPM is not CPM, and this is the big one

They sound alike and measure opposite sides of the transaction.

|         | Denominator              | Numerator                                     |
| ------- | ------------------------ | --------------------------------------------- |
| **RPM** | Every view               | Your revenue, after YouTube's share           |
| **CPM** | Monetised ad impressions | What advertisers paid, before YouTube's share |

So CPM is always much higher than RPM, on every channel, and the gap is not a
problem to fix. It is two different ratios.

Specifically: not every view carries an ad, so the RPM denominator is far
larger. And CPM is what the advertiser paid, while RPM is what reached you
after YouTube took its cut.

Comparing your RPM against somebody's quoted CPM and concluding you are
underpaid is the most common mistake in creator revenue discussions.

## Estimated means estimated

Every one of these is adjusted after publication for invalid traffic and
advertiser disputes. The last few days of a window move, and a month only
finalises well into the following one, when YouTube closes it for payment.

So a month-to-date revenue figure is a forecast, and a comparison against
last month's final figure is not like for like until this month closes.

## Currency

Revenue is reported in your AdSense account's currency, and YouTube returns
it as a decimal rather than as minor units: `1234.56`, not `123456`. Convert
to integer minor units before storing it and never hold money in a float.

## The scope

`https://www.googleapis.com/auth/yt-analytics-monetary.readonly`, in addition
to the read-only YouTube scope.

A channel outside the YouTube Partner Programme has no revenue to report, and
the API answers with an error rather than zero. That is the correct
behaviour: zero revenue and no revenue programme are different states, and
reporting the second as the first would be a lie with a number attached.

## In the notch

Notch Metrics reports
[YouTube estimated revenue](/sources/youtube/revenue),
[ad revenue](/sources/youtube/ad-revenue) and
[RPM](/sources/youtube/rpm) in the MacBook notch, with RPM computed over the
whole window rather than averaged across daily rates, and the page saying
plainly that it is not CPM.

[Everything YouTube reports](/sources/youtube), or
[download Notch Metrics](/download).
