---
title: "How to track Polar subscription cancellations"
description: "What Polar counts as a subscription ending, why trials that lapse are not churn, and how to read cancellations against new subscriptions."
date: 2026-10-11
author: Notch Metrics
tags: [polar, churn, api]
pillar: polar-revenue-in-your-notch
faq:
  - question: How do I get Polar churn from the API?
    answer: >-
      Call GET /v1/metrics/ with metrics=churned_subscriptions. It returns
      subscriptions that ended in each period, with no paging. Ask for
      new_subscriptions in the same call to get both halves.
  - question: Does a cancelled Polar subscription count as churn immediately?
    answer: >-
      No. A subscription cancelled with the period left to run stays active and
      keeps paying until it expires. Polar counts it when it actually ends,
      which is the bucket that lines up with active subscriptions.
  - question: Do lapsed Polar trials count as churn?
    answer: >-
      No. A trial that ends without converting never started paying, so it
      belongs to the top of the funnel rather than to churn. Polar excludes
      trials from MRR, active subscriptions and churn alike.
  - question: What does past_due mean on a Polar subscription?
    answer: >-
      A payment is failing and dunning is retrying it. It is involuntary churn
      in progress rather than churn, and it is the kind you can actually fix. By
      the time it becomes a cancellation, several days of retries have already
      happened.
  - question: Does Polar give a churn rate or a churn count?
    answer: >-
      The metrics endpoint gives a count. A rate needs a denominator, and active
      at the start of the window, active plus new, and MRR are all defensible
      choices that produce different numbers.
---

## When does a Polar subscription count as cancelled?

When it ends, not when somebody clicks.

A Polar subscription can be revoked immediately, or cancelled with the
current period left to run. In the second case the customer keeps access and
keeps being counted as active until the period they paid for expires. An
annual plan cancelled in January ends the following January.

Polar's own churn metric buckets by the end, and that is the behaviour you
want. It lines up with active subscriptions: every drop in one is a bump in
the other, which is what makes the two readable as a pair.

## The call

```bash
curl -s 'https://api.polar.sh/v1/metrics/?start_date=2026-09-01&end_date=2026-10-01&interval=day&metrics=churned_subscriptions&timezone=Europe/London' \
  -H 'Authorization: Bearer polar_oat_...'
```

One call, one series, no paging. Ask for `new_subscriptions` in the same
request and you have both halves:

```
metrics=churned_subscriptions,new_subscriptions
```

That is the pair worth plotting. The difference is net movement, and net
movement is what decides whether MRR goes up.

## Trials are not churn

A trial that ends without converting never started paying. It belongs to the
top of your funnel, not to churn, and counting it here makes a healthy flow
of trials look like a leak.

Polar excludes trials from MRR and from active subscriptions, so it excludes
them here too. If your trial-to-paid rate is what you actually want to know,
that is a different measurement against your trial starts.

## The subscription states

Polar subscriptions move between several states and only one of them is
churn.

| State      | Churn?                                          |
| ---------- | ----------------------------------------------- |
| `active`   | No                                              |
| `trialing` | No, and not counted as active either            |
| `past_due` | No. A payment is failing and dunning is running |
| `canceled` | Not yet, if the period is still running         |
| `revoked`  | Yes. Access has ended                           |

`past_due` is the one worth watching separately. It is involuntary churn in
progress, and unlike somebody who chose to leave it is the kind you can
actually fix. By the time it becomes a cancellation, several days of retries
have already happened and the figure in your churn series lags the card that
failed.

## Counting is not a rate

This gives you subscriptions lost. A churn rate needs a denominator, and
there are at least three defensible ones: active subscriptions at the start
of the window, active at the start plus new, or MRR rather than count.

Pick one and write it down beside the code. A churn rate whose definition
moved is worse than no churn rate, because the trend line still looks real.

## In the notch

Notch Metrics reports
[Polar churned subscriptions](/sources/polar/churned-subscribers) as a count,
bucketed by when the subscription ended, with a sparkline and a comparison
against the previous window. Put it beside
[new subscriptions](/sources/polar/new-subscribers) and
[MRR](/sources/polar/mrr) and the three say what is happening.

It reports a count rather than a rate, deliberately: the denominator
everybody means by "churn rate" differs by company, and guessing yours would
produce a number you could not defend.

[Everything Polar reports](/sources/polar), or
[download Notch Metrics](/download).
