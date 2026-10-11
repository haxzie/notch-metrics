---
title: "How to track trial to paid conversion in RevenueCat"
description: "Active trials is a snapshot, not a funnel. How to measure trial conversion properly, and why the obvious ratio is wrong."
date: 2026-10-11
author: Notch Metrics
tags: [revenuecat, trials, api]
pillar: revenuecat-mrr-and-trials-on-your-mac
faq:
  - question: Can I calculate trial conversion from RevenueCat active trials and active subscriptions?
    answer: >-
      No. Those are snapshots of two different populations at the same instant,
      and a trial started today has not had the chance to convert. Dividing one
      by the other produces a number that moves convincingly and means nothing.
  - question: What does RevenueCat active trials count?
    answer: >-
      Free trials running right now, including ones that have been cancelled,
      until they convert to paid or expire. Read it as queue depth: a cohort
      that will decide within whatever trial length the store is enforcing.
  - question: Does a CANCELLATION webhook during a trial mean the trial ended?
    answer: >-
      No. It means auto-renew was switched off and the trial keeps running to
      its end date. Count it as intent rather than as an outcome, or you report
      people as lost while they are still using the app.
  - question: How do I measure RevenueCat trial conversion properly?
    answer: >-
      As a cohort, from webhooks. Record INITIAL_PURCHASE with period_type TRIAL
      as the start, then look for the first RENEWAL within the trial length plus
      a grace margin. EXPIRATION without a renewal is a lapse.
  - question: Should I split trial conversion by store?
    answer: >-
      Yes. Trial lengths are configured per store product and App Store and Play
      Store rarely match exactly, so a single blended rate is an average of two
      different experiments.
---

## Why is trial conversion hard to measure?

Because the obvious calculation is wrong and it looks right.

Take active trials, take active subscriptions, divide. You now have a number
that moves, feels meaningful, and answers nothing. The two figures are
snapshots of different populations at the same instant, and a trial started
today has not had the chance to convert.

Conversion is a cohort question. Of the people who started a trial in a given
week, how many were paying when it ended? Answering it needs the start and
the outcome tied together, which no single snapshot gives you.

## What active trials actually is

A count of free trials running right now, including cancelled ones, until
they convert to paid or expire.

Read it as queue depth. Trials doubling means a cohort arrived that will
decide, one way or the other, within whatever trial length the store is
enforcing. The number falling means they decided, and it does not say which
way.

That makes it a genuinely useful leading indicator and a useless conversion
rate.

## The pair that tells you something

Put [active trials](/sources/revenuecat/trials) next to
[active subscriptions](/sources/revenuecat/active-subscribers) and watch them
together over a trial length.

- Trials fall, subscriptions rise. Conversion.
- Trials fall, subscriptions flat. They left.
- Trials rise, subscriptions flat. The cohort has not decided yet.

That is not a conversion rate, but it is directionally honest, and it is
available from one endpoint with no extra work.

## Measuring it properly, with webhooks

For a real conversion rate you need the cohort, and that means recording
events as they happen.

RevenueCat sends `INITIAL_PURCHASE` with a `period_type` that distinguishes a
trial start, and then one of several outcomes later.

```js
// Sketch. Store these and the ratio becomes a query rather than a guess.
const OUTCOMES = {
  INITIAL_PURCHASE: "started", // period_type TRIAL
  RENEWAL: "converted", // first renewal after a trial is the conversion
  CANCELLATION: "cancelled", // intent to leave, trial still running
  EXPIRATION: "lapsed", // trial ended without paying
};
```

`CANCELLATION` during a trial is the signal people misread. It does not mean
the trial ended. It means auto-renew was switched off, and the trial keeps
running to its end date. Count it as intent, not as an outcome, or you will
report people as lost while they are still using the app.

The conversion rate is then: trials started in week N, divided into those
whose first `RENEWAL` arrived within the trial length plus a grace margin.

## Two stores, two clocks

A project shipping to both App Store and Play Store mixes trial lengths,
because the trial is configured per store product and the two rarely match
exactly. A single blended conversion rate across both is an average of two
different experiments.

Split by store before you draw conclusions about a trial length change.

## Billing grace periods blur the end

A subscription that converts but whose first payment fails enters a grace
period rather than expiring. Depending on where you draw the line, that user
converted, or has not yet, or never will.

Pick a rule, write it down, and apply it consistently. The rate matters far
less than the rate being comparable to last month's.

## In the notch

Notch Metrics reports
[RevenueCat active trials](/sources/revenuecat/trials) as a live snapshot of
how many are running, beside
[active subscriptions](/sources/revenuecat/active-subscribers),
[MRR](/sources/revenuecat/mrr) and
[new customers](/sources/revenuecat/new-users).

It deliberately does not show a conversion rate. A rate computed from two
snapshots would be a number that moves convincingly and means nothing, and
the real one needs a cohort nobody can derive from a single API call.

[Everything RevenueCat reports](/sources/revenuecat), or
[download Notch Metrics](/download).
