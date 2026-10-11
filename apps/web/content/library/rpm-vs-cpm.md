---
title: "RPM against CPM"
description: "RPM is what you earn per thousand views. CPM is what advertisers pay per thousand ad impressions. Why CPM is always the bigger number."
date: 2026-10-11
author: Notch Metrics
tags: [rpm, cpm, youtube, glossary]
kind: glossary
term: Revenue per mille
faq:
  - question: What is the difference between RPM and CPM?
    answer: >-
      RPM is your revenue after the platform's share, divided by every view. CPM
      is what advertisers paid before the platform's share, divided by monetised
      ad impressions only. Both differences push the same way, which is why CPM
      is always much higher.
  - question: Why is my RPM so much lower than CPM?
    answer: >-
      Because not every view carries an ad, so the RPM denominator is far
      larger, and because RPM is what reached you after the platform took its
      cut while CPM is what the advertiser was billed. The gap is structural,
      not a sign of anything wrong.
  - question: Which should I track, RPM or CPM?
    answer: >-
      RPM. It is the only one that answers what a view is worth to you. CPM is
      the right number for understanding advertiser demand in your niche, and it
      tells you nothing about your own earnings.
  - question: Why did my RPM drop without my CPM changing?
    answer: >-
      Usually a format or audience change rather than a market one. Shorter
      videos carry fewer ad slots, a shift towards Shorts lowers RPM sharply,
      and a change in audience country changes rates entirely.
  - question: How should RPM be calculated over a week?
    answer: >-
      Total revenue divided by total views, times a thousand. Not the average of
      the daily RPM values: a quiet day with one high-value view produces an
      enormous daily figure and should contribute almost nothing.
---

**RPM is revenue per mille: your earnings divided by every view, times a
thousand. CPM is cost per mille: what advertisers paid, divided by monetised
ad impressions, times a thousand.**

They sound alike, they are quoted interchangeably, and they measure opposite
sides of the same transaction.

## The two differences that matter

|             | RPM                                          | CPM                               |
| ----------- | -------------------------------------------- | --------------------------------- |
| Denominator | **Every view**                               | **Monetised ad impressions only** |
| Numerator   | Your revenue, **after** the platform's share | Advertiser spend, **before** it   |

Both differences push the same way, which is why CPM is always substantially
higher than RPM on every channel.

**The denominator.** Not every view carries an ad. Viewers with ad blockers,
viewers on Premium, videos that were not monetised, and plenty of ordinary
playbacks produce no ad impression at all. The RPM denominator is therefore
much larger than the CPM one.

**The numerator.** CPM is what the advertiser was billed. RPM is what reached
you after the platform took its cut.

## Why this matters practically

The most common mistake in creator revenue discussions is comparing your RPM
against somebody's quoted CPM and concluding you are being underpaid.

You are comparing a post-revenue-share figure over all views against a
pre-revenue-share figure over ad impressions. The gap is structural. It is
not a sign of anything.

If you want to compare yourself to somebody, compare RPM to RPM. If you want
to understand advertiser demand in your niche, CPM is the right number and
your own revenue is not.

## RPM is the one worth watching

Because it is the only one that answers "what is a view worth to me".

A rising CPM with a falling RPM means advertisers are paying more and fewer
of your views are carrying ads, which is a format or audience change rather
than a market one. A rising RPM is money.

RPM also moves for reasons that have nothing to do with ad rates: longer
videos carry more ad slots, a different audience country changes rates
entirely, and a shift towards Shorts usually lowers it sharply.

## Compute it over the window

RPM is a ratio, so it has the same trap as every ratio.

```
Right:  (total_revenue / total_views) * 1000
Wrong:  mean(daily_revenue / daily_views * 1000)
```

A quiet day with one high-value view produces an enormous daily RPM and
should contribute almost nothing to the period figure. Averaging the points
weights it equally with a day of ten thousand views, and the result jumps
around for no reason.

## RPM in Notch Metrics

[YouTube RPM](/sources/youtube/rpm) is computed over the whole window rather
than averaged across daily rates, which is how YouTube Studio reports it.
The page says plainly that it is not CPM.

Place it beside [estimated revenue](/sources/youtube/revenue),
[ad revenue](/sources/youtube/ad-revenue) and
[views](/sources/youtube/views).

[How to read estimated revenue and RPM from YouTube Analytics](/blog/read-estimated-revenue-and-rpm-from-youtube-analytics)
