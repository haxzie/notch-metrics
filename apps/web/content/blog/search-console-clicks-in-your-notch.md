---
title: "Search Console clicks in your MacBook notch"
description: "Clicks, impressions, CTR and average position from Google Search Console, in the strip of glass around your Mac's camera."
date: 2026-10-11
author: Notch Metrics
tags: [google-search-console, seo, mac]
faq:
  - question: How do I see Search Console clicks on my Mac?
    answer: >-
      Install Notch Metrics, connect Google Search Console over OAuth, pick the
      property, and place the clicks widget in the MacBook notch. Hover the
      camera housing and the figure is there.
  - question: Why does my Search Console chart always dip at the end?
    answer: >-
      Because Search Console data settles over two to three days, so the newest
      buckets read low until it does. The droop is a reporting artefact rather
      than a drop in traffic, and it appears on every site on every refresh.
  - question: Why is lower better for average position?
    answer: >-
      Because it is a rank rather than a count. Position 8.1 is better than
      12.4, so an improving line goes down. Notch Metrics formats it with one
      decimal and no compacting to make clear it is a rank.
  - question: What Google permissions does the Search Console connector ask for?
    answer: >-
      Read-only Webmasters scope, and nothing else. Search Console connects over
      OAuth, so nothing is typed in, and the resulting token is encrypted on the
      server rather than stored on your Mac.
  - question: Can I track more than one Search Console property?
    answer: >-
      Yes, as separate connections. The connector pauses after you authorise so
      you can pick which property to read, because most accounts have several.
---

Search Console is where you find out whether yesterday's post landed. It is
also a slow interface you load, filter, and close.

## How do you watch Search Console without opening it?

Notch Metrics puts the four numbers in the MacBook notch. Collapsed, a thin
strip. Hover the camera housing and it expands over whatever you were doing.
Move away and it folds back.

## What Search Console reports

| Number                                                              | What it is                                 |
| ------------------------------------------------------------------- | ------------------------------------------ |
| [Clicks](/sources/google-search-console/clicks)                     | Visits that started in Google Search       |
| [Impressions](/sources/google-search-console/impressions)           | How often you appeared in results          |
| [CTR](/sources/google-search-console/ctr)                           | Clicks over impressions, across the window |
| [Average position](/sources/google-search-console/average-position) | Where you sat, lower is better             |

## The two to three day lag, which changes how you read all of them

Search Console data settles over roughly two to three days. The newest
buckets read low until it does.

So a daily sparkline droops at the right-hand end, on every site, on every
refresh. That droop is a reporting artefact and not a drop in traffic. Read
the trend from the settled part of the window.

It also means the honest answer to "how did today go" is that you will find
out on Thursday. Every [metric page](/sources/google-search-console) says so
rather than letting the chart imply otherwise.

## Average position reads backwards

Lower is better. A move from 12.4 to 8.1 is an improvement and the line goes
down, which is the opposite of every other widget in the notch. It is
formatted with one decimal and no compacting to make clear it is a rank
rather than a count.
[Why that matters](/sources/google-search-console/average-position).

## OAuth, and picking a site

Search Console connects over OAuth with read-only Webmasters scope. After
approving, you pick which property to read, because most accounts have
several.
[What the Search Console connector asks for](/sources/google-search-console).

Nothing is typed in. The token is encrypted on the server and never reaches
your Mac. The connector is marked beta: it connects and returns figures, and
the edges are still being worked on.

## Alongside everything else

Traffic from [Plausible](/sources/plausible) and
[Google Analytics](/sources/google-analytics), revenue from
[Stripe](/sources/stripe), video from [YouTube](/sources/youtube).
[Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $14 a month
or $79 a year. [Download Notch Metrics](/download).
