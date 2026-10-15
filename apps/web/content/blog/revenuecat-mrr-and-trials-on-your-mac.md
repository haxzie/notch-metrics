---
title: "RevenueCat MRR and trials on your Mac"
description: "MRR, revenue, active subscriptions and live trials from RevenueCat, in the MacBook notch. Hover to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [revenuecat, mrr, mac]
faq:
  - question: How do I see RevenueCat MRR on my Mac?
    answer: >-
      Install Notch Metrics, connect RevenueCat on the web with a v2 secret key
      and a project id, and place the MRR widget in the MacBook notch. Hover the
      camera housing and the figure is there.
  - question: Is RevenueCat revenue net of Apple and Google commission?
    answer: >-
      No. The revenue figure is gross, before store commission and before tax.
      What reaches your bank is meaningfully less, and the gap depends on which
      store and which year of the subscription.
  - question: Why do RevenueCat new and active customers ignore the widget's range?
    answer: >-
      Because RevenueCat computes them over a fixed 28-day window on its
      Overview, and that window is not configurable. The metric pages say so
      rather than letting a range control appear to work when it does not.
  - question: What is the difference between RevenueCat active subscriptions and active trials?
    answer: >-
      Active subscriptions counts paid subscriptions, including ones cancelled
      or in a grace period until they expire, with trials excluded. Active
      trials counts free trials running right now. Placed together, trials
      falling while subscriptions rise is conversion.
  - question: Does Notch Metrics compute its own RevenueCat MRR?
    answer: >-
      No. It reads RevenueCat's own MRR from the project overview, so the notch
      and the RevenueCat dashboard agree rather than offering a second opinion
      on somebody else's headline number.
---

App subscriptions live behind two stores and one dashboard. RevenueCat
unifies the stores. The dashboard is still a tab.

## How do you watch RevenueCat without opening it?

Notch Metrics renders the figures in the MacBook notch. Collapsed, a thin
strip. Hover the camera housing and it expands over whatever you were doing.
Move away and it folds back to the shape it had.

## What RevenueCat reports

| Number                                                         | What it is                               |
| -------------------------------------------------------------- | ---------------------------------------- |
| [MRR](/sources/revenuecat/mrr)                                 | RevenueCat's own MRR for the project     |
| [Revenue](/sources/revenuecat/revenue)                         | Gross, before store commission and tax   |
| [Active subscriptions](/sources/revenuecat/active-subscribers) | Paid, trials excluded                    |
| [Active trials](/sources/revenuecat/trials)                    | Free trials running right now            |
| [New customers](/sources/revenuecat/new-users)                 | First seen in the last 28 days           |
| [Active customers](/sources/revenuecat/active-users)           | Contacted RevenueCat in the last 28 days |

Notch Metrics reads MRR from RevenueCat's own overview endpoint rather than
recomputing it, so the notch and the RevenueCat dashboard agree. Reporting a
second opinion on somebody else's headline number is how two screens in the
same company end up disagreeing about the business.

## Two things that are not obvious

**Revenue is gross.** Before Apple's and Google's commission, and before tax.
What reaches your bank is meaningfully less, and the gap depends on which
store and which year of the subscription.

**The customer windows are fixed at 28 days.** RevenueCat computes new and
active customers over its own 28-day window on the Overview, and that window
ignores whatever range you set on the widget. The
[new customers](/sources/revenuecat/new-users) and
[active customers](/sources/revenuecat/active-users) pages say so plainly,
because a widget that silently ignores its own range control is worse than
one that explains why.

## Trials beside subscriptions

[Active trials](/sources/revenuecat/trials) is the earliest number in a
mobile subscription funnel. It is a snapshot of how many people are inside a
free trial right now, not how many started one in the window.

Place it next to active subscriptions and the pair reads properly: trials
falling while subscriptions rise is conversion, and trials falling while
subscriptions hold flat is not.

## Connecting

A RevenueCat v2 secret key and a project id.
[What the connector asks for](/sources/revenuecat). The key is encrypted on
the server with a key unique to that one connection, so the Mac app never
holds it.

## Alongside everything else

Revenue also comes from [Stripe](/sources/stripe), [Polar](/sources/polar),
[Paddle](/sources/paddle), [Dodo Payments](/sources/dodopayments) and
[Lemon Squeezy](/sources/lemonsqueezy). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
