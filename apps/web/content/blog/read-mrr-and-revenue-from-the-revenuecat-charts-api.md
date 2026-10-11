---
title: "How to read MRR and revenue from the RevenueCat Charts API"
description: "The overview endpoint, the metric ids worth knowing, and why RevenueCat revenue is gross of Apple's and Google's commission."
date: 2026-10-11
author: Notch Metrics
tags: [revenuecat, revenue, api]
pillar: revenuecat-mrr-and-trials-on-your-mac
faq:
  - question: Which RevenueCat endpoint returns MRR?
    answer: >-
      GET /v2/projects/{project_id}/metrics/overview. It returns the dashboard
      header figures, including MRR, revenue, active subscriptions and active
      trials, in a metrics array that should be read by id rather than by
      position.
  - question: Is RevenueCat revenue before or after Apple's commission?
    answer: >-
      Before. The revenue figure is gross across every app in the project,
      before store commission and before taxes. The commission depends on the
      programme and on how long the subscriber has been subscribed, so the gap
      is not a constant you can multiply by.
  - question: Why does today's RevenueCat revenue look low?
    answer: >-
      Because it is still filling. Transactions arrive from the stores with a
      lag, so the newest day reads low and settles over the following hours. A
      daily chart droops at the right-hand end on every refresh.
  - question: Can I change the window on RevenueCat new customers?
    answer: >-
      No. new_customers and active_customers are computed over a fixed 28-day
      window that is not a parameter. Asking the endpoint for a different range
      does not change them.
  - question: Should I compute my own MRR instead of using RevenueCat's?
    answer: >-
      Usually not. Mobile subscriptions have introductory offers, promotional
      offers, family sharing, grace periods and two stores reporting
      differently, and RevenueCat has already decided what to do with each. A
      second opinion is a second number to defend.
---

## Where does RevenueCat expose its dashboard numbers?

Under v2 project metrics. The Overview endpoint returns the figures the
dashboard header shows, and the Charts API gives you the series behind the
dashboard's graphs.

For a headline number, Overview is one call and no paging:

```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/metrics/overview' \
  -H 'Authorization: Bearer sk_...'
```

## Read metrics by id

The response is an array, and an array's order is not a contract. A new
metric appearing in the middle would silently shift every positional read
after it.

```js
const by = (body, id) => body.metrics?.find((m) => m.id === id)?.value ?? null;

const mrr = by(body, "mrr");
const revenue = by(body, "revenue");
const subs = by(body, "active_subscriptions");
const trials = by(body, "active_trials");
```

## What MRR means here

RevenueCat's own figure: active paid subscriptions normalised to a month, as
shown on the Overview. It is a snapshot of the book right now.

Read RevenueCat's rather than computing your own. Mobile subscriptions have
more edges than card subscriptions do, with introductory offers, promotional
offers, family sharing, billing grace periods and two stores reporting
differently, and RevenueCat has already decided what to do with each. A
second opinion is a second number to defend.

## Revenue is gross, and the gap is large

This catches everybody once. RevenueCat revenue is gross across every app in
the project for the days in the window, **before store commission and before
taxes**.

Apple and Google take a commission that depends on the programme you are in
and on how long the subscriber has been subscribed. Tax comes off separately
and varies by country. The money that reaches your bank is well below the
revenue figure, and the difference is not a constant you can multiply by.

If you want proceeds rather than revenue, that is a different question and
RevenueCat exposes it separately. Label your chart for whichever one you
chose, because a revenue figure presented as income is the kind of mistake
that reaches a board deck.

## Today is partial

The newest day in any window is still filling. Transactions arrive from the
stores with a lag, so today's figure reads low and settles over the following
hours. A daily chart droops at the right-hand end on every refresh.

Read trends from the settled part. If you need to know whether today was
good, you will find out tomorrow.

## The 28-day metrics

`new_customers` and `active_customers` on the Overview are computed over a
fixed 28-day window. That window is RevenueCat's and it is not a parameter:
asking the endpoint for a different range does not change them.

Any interface that offers a range selector next to those two numbers is
either ignoring the selector or inventing the answer. Say which.

## In the notch

Notch Metrics reads this endpoint and reports
[RevenueCat MRR](/sources/revenuecat/mrr),
[revenue](/sources/revenuecat/revenue),
[active subscriptions](/sources/revenuecat/active-subscribers),
[trials](/sources/revenuecat/trials),
[new customers](/sources/revenuecat/new-users) and
[active customers](/sources/revenuecat/active-users) in the MacBook notch.

The two 28-day metrics say on their own pages that the window is fixed and
ignores the widget's range, because a control that does nothing is worse than
no control at all.

[Everything RevenueCat reports](/sources/revenuecat), or
[download Notch Metrics](/download).
