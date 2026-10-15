---
title: "YouTube views and revenue on your Mac"
description: "Views, watch time, subscribers, revenue and RPM from YouTube, in the MacBook notch. Hover to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [youtube, creator, mac]
faq:
  - question: How do I see YouTube views on my Mac?
    answer: >-
      Install Notch Metrics, connect YouTube over OAuth, pick the channel, and
      place the views widget in the MacBook notch. Hover the camera housing and
      the figure is there.
  - question: Which timezone does YouTube Analytics use?
    answer: >-
      America/Los_Angeles, regardless of where you are. A view at nine in the
      evening in London lands on the previous Pacific day, which is usually why
      a figure disagrees with your sense of when a spike happened.
  - question: Why is my YouTube subscriber count rounded?
    answer: >-
      Because YouTube rounds public and Analytics subscriber totals above a
      certain channel size, so 12,345 reads as 12,300. Notch Metrics shows the
      total without a sparkline for that reason, but the change against the
      previous window comes from Analytics and is exact.
  - question: What is the difference between YouTube estimated revenue and ad revenue?
    answer: >-
      Estimated revenue includes advertising, channel memberships, Super Chat,
      Super Thanks and Premium watch-time revenue. Ad revenue is the advertising
      part alone. A flat total with falling ad revenue means memberships are
      carrying the channel.
  - question: Is YouTube revenue in Notch Metrics final?
    answer: >-
      No, it is estimated. YouTube adjusts for invalid traffic and advertiser
      disputes after the fact, so the last few days of any window move and a
      month finalises well into the following one.
---

YouTube Studio is a good analytics product and a heavy page. Checking one
number costs you a load, a date picker and a scroll.

## How do you watch YouTube without Studio?

Notch Metrics puts the figures in the MacBook notch. Collapsed, a thin strip.
Hover the camera housing and it expands over whatever you were doing. Move
away and it folds back to the shape it had.

## What YouTube reports

Ten numbers, the richest connector in the product.

| Number                                                          | What it is                            |
| --------------------------------------------------------------- | ------------------------------------- |
| [Views](/sources/youtube/views)                                 | Validated views in the window         |
| [Watch time](/sources/youtube/watch-time)                       | Total minutes, shown in hours         |
| [Average view duration](/sources/youtube/average-view-duration) | Watch time over views                 |
| [Subscribers](/sources/youtube/subscribers)                     | The channel total, rounded by YouTube |
| [New subscribers](/sources/youtube/new-subscribers)             | Gained in the window, gross           |
| [Likes](/sources/youtube/likes)                                 | Likes added in the window             |
| [Comments](/sources/youtube/comments)                           | Comments added, replies included      |
| [Estimated revenue](/sources/youtube/revenue)                   | Everything the channel earned         |
| [Ad revenue](/sources/youtube/ad-revenue)                       | The advertising part alone            |
| [RPM](/sources/youtube/rpm)                                     | Revenue per thousand views            |

## Three things worth knowing up front

**Days are Pacific Time.** YouTube Analytics buckets everything in
America/Los_Angeles regardless of where you are. A view at nine in the
evening in London lands on the previous Pacific day, and a figure that
disagrees with your sense of when a spike happened by a day is usually this.

**Subscribers is rounded.** Above a certain size YouTube rounds the public
and Analytics totals, so 12,345 reads as 12,300. The widget shows the total
without a sparkline, because a sparkline of a rounded series draws steps and
reads as though growth stopped and restarted. The change against the previous
window comes from Analytics and is exact, so the arrow is right even where
the total is rounded.
[Why that is](/sources/youtube/subscribers).

**Revenue is estimated and it settles.** YouTube adjusts for invalid traffic
and advertiser disputes after the fact, so the last few days of any window
move and a month finalises well into the following one.

## Revenue, split

Estimated revenue is everything: advertising, channel memberships, Super
Chat, Super Thanks and Premium watch-time revenue.
[Ad revenue](/sources/youtube/ad-revenue) is the advertising part alone.

Placing both is the useful move. A channel whose total is flat while ad
revenue falls is being carried by memberships, which is a different business
from the one the total implies.

## Connecting

OAuth, with read-only YouTube scope and the monetary analytics scope for the
revenue figures. After approving you pick which channel, because an account
can manage several.
[What the YouTube connector asks for](/sources/youtube).

Nothing is typed in, and the token is encrypted on the server rather than
stored on your Mac.

## Alongside everything else

Search from [Search Console](/sources/google-search-console), traffic from
[Plausible](/sources/plausible), revenue from [Stripe](/sources/stripe).
[Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
