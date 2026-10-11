---
title: "GA4 visitors in your MacBook notch"
description: "Active users, new users, sessions and page views from Google Analytics 4, in the strip of glass around your Mac's camera."
date: 2026-10-11
author: Notch Metrics
tags: [google-analytics, ga4, mac]
faq:
  - question: How do I see GA4 visitors on my Mac?
    answer: >-
      Install Notch Metrics, connect Google Analytics over OAuth, pick the GA4
      property, and place the active users widget in the MacBook notch. Hover
      the camera housing and the figure is there.
  - question: Does Notch Metrics work with Universal Analytics?
    answer: >-
      No. This is GA4 only. Universal Analytics stopped processing data and its
      reporting API is no longer the one to build against, so a property id
      beginning with UA- has nothing to connect.
  - question: Why do GA4 daily bars not add up to the weekly figure?
    answer: >-
      Because active users is de-duplicated over the whole window, as Google
      reports it. One person on three days is one user and three bars, so a
      weekly figure is not the sum of seven daily ones.
  - question: What Google permissions does Notch Metrics ask for?
    answer: >-
      Read-only analytics scope, and nothing else. Nothing is typed in because
      Google Analytics connects over OAuth, and the resulting token is encrypted
      on the server rather than stored on your Mac.
  - question: Why does Notch Metrics ask me to pick a GA4 property?
    answer: >-
      Because a Google account usually has several and reading the wrong one
      would be worse than asking. The connector pauses after you authorise so
      you can choose.
---

GA4 is thorough and slow. Loading a report to read one number is a
disproportionate amount of clicking.

## How do you watch GA4 without opening GA4?

Notch Metrics puts the figures in the MacBook notch. Collapsed, a thin strip.
Hover the camera housing and it expands over whatever you were doing. Move
away and it folds back to the shape it had.

## What Google Analytics reports

| Number                                                 | What it is                       |
| ------------------------------------------------------ | -------------------------------- |
| [Active users](/sources/google-analytics/active-users) | GA4 `activeUsers`, de-duplicated |
| [New users](/sources/google-analytics/new-users)       | First-time users in the window   |
| [Sessions](/sources/google-analytics/sessions)         | Sessions started in the window   |
| [Page views](/sources/google-analytics/pageviews)      | GA4 `screenPageViews`            |

## The de-duplication that explains the chart

The headline active user figure is de-duplicated over the whole window, as
Google reports it. The chart is per day, so its bars do not add up to the
headline: one person on three days is one user and three bars.

A weekly active user figure is not the sum of seven daily ones. Any tool
whose bars sum to its headline is showing you daily actives seven times.

## OAuth, and picking a property

Google Analytics connects over OAuth with read-only analytics scope. After
you approve, you pick which GA4 property to read, because a Google account
usually has several and guessing would be worse than asking.
[What the Google Analytics connector asks for](/sources/google-analytics).

Nothing is typed in. The token is encrypted on the server and never reaches
your Mac.

## Universal Analytics is gone

This is GA4 only. Universal Analytics stopped processing data and its
reporting API is no longer the one to build against. If you are looking at a
property id beginning with `UA-`, there is nothing to connect.

## Beta

The connector is marked beta on
[its page](/sources/google-analytics). It connects and returns figures; the
edges are still being worked on.

## Alongside everything else

Revenue from [Stripe](/sources/stripe), search from
[Search Console](/sources/google-search-console), privacy-friendly analytics
from [Plausible](/sources/plausible), product analytics from
[PostHog](/sources/posthog). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $14 a month
or $79 a year. [Download Notch Metrics](/download).
