---
title: "How to measure Stripe subscriber churn"
description: "Cancelled at period end is not cancelled. Here is how to count Stripe churn honestly, and why a churn count is not a churn rate."
date: 2026-10-11
author: Notch Metrics
tags: [stripe, churn, api]
pillar: stripe-mrr-on-your-mac
faq:
  - question: How do I count churned subscribers with the Stripe API?
    answer: >-
      List subscriptions with status canceled and filter on ended_at falling
      inside your window. There is no server-side date filter for ended_at, so
      the filtering happens client-side after paging.
  - question: What is the difference between canceled_at and ended_at in Stripe?
    answer: >-
      canceled_at is when somebody asked to cancel. ended_at is when the
      subscription actually stopped. For a subscription cancelled at period end
      they can be a year apart, and ended_at is the one that lines up with your
      active subscriber count.
  - question: Does cancel_at_period_end mean a Stripe subscription has churned?
    answer: >-
      Not yet. The subscription stays active and keeps paying until the period
      they bought runs out. Counting it as churn on the day somebody clicks
      makes churn spike while revenue does not move.
  - question: How do I separate involuntary churn in Stripe?
    answer: >-
      Involuntary churn arrives through past_due and unpaid rather than straight
      to canceled, after however long your dunning settings retry. Track
      subscriptions entering past_due separately. Failed payments are the churn
      you can actually fix.
  - question: What is the correct denominator for a Stripe churn rate?
    answer: >-
      There is no single correct one. Customers at the start of the period,
      customers at the start plus new customers, and MRR rather than customers
      all give different figures. Pick one, write it down, and never change it
      quietly.
  - question: How do I get Stripe churn without paging the whole subscription history?
    answer: >-
      Listen for the customer.subscription.deleted webhook and record the date
      yourself. The subscriptions list filters on created, not ended_at, so
      without your own record you page every cancellation you have ever had.
---

## What counts as a churned Stripe subscriber?

The question sounds trivial and it is the whole problem. Stripe has two
shapes of cancellation and they happen at different times.

One ends the subscription now. The other sets `cancel_at_period_end`, which
leaves the subscription `active` until the period they paid for runs out.
Somebody who cancels an annual plan today is still a paying customer for the
next eleven months.

Count them on the day they clicked and your churn figure spikes today while
your revenue does not move for a year. Count them when the subscription
actually ends and today's churn number tells you nothing about today's
cancellations. Both are defensible. Only one can be true at a time.

## Counting by when it ended

```js
async function churned(stripe, from, to) {
  let count = 0;

  for await (const sub of stripe.subscriptions.list({
    status: "canceled",
    limit: 100,
  })) {
    const endedAt = (sub.ended_at ?? 0) * 1000;
    if (endedAt >= from && endedAt < to) count += 1;
  }

  return count;
}
```

`ended_at` is when the subscription actually stopped. `canceled_at` is when
somebody asked. For a subscription cancelled immediately they are the same
second. For one cancelled at period end they can be a year apart.

This is the bucket that lines up with your active subscriber count, which is
why it is the one worth defaulting to. A churn series that disagrees with the
movement in active subscribers is a series nobody will trust.

## The filter you cannot use

`subscriptions.list` has no date filter on `ended_at`. It filters on
`created`, which is when the subscription began, and that is useless here.
You page the cancelled list and filter client-side, which means a business
with years of history pages through every subscription it has ever lost to
answer a question about last week.

Two ways out. Listen for `customer.subscription.deleted` on a webhook and
record the date yourself, which is the right answer for anything serious. Or
cache aggressively and accept the paging, which is fine below a few thousand
cancellations.

## Involuntary churn hides somewhere else

A subscription whose payment keeps failing does not go straight to
`canceled`. It goes to `past_due`, then to `unpaid` or `canceled` depending
on your dunning settings, and the gap is however long you told Stripe to
retry.

So your churn figure lags the failure that caused it by days or weeks, and a
dunning configuration change moves the whole series. Worth knowing before you
read a step in the chart as a product problem.

Failed payments are also the churn you can actually fix. Separating
involuntary churn from people who chose to leave is usually the highest
return analysis a subscription business can do.

## A count is not a rate

Everything above counts subscriptions lost. A churn rate divides that by a
denominator, and the denominator is where every argument happens.

Customers at the start of the period. Customers at the start plus new
customers. MRR rather than customers. Each gives a different number and each
has a published blog post calling it the correct one.

Pick one, write it down beside the code, and never change it quietly. A churn
rate whose definition moved is worse than no churn rate, because the trend
line looks real.

## In the notch

Notch Metrics reports
[Stripe churned subscribers](/sources/stripe/churned-subscribers) as a count,
bucketed by cancellation time, with a sparkline and a comparison against the
previous window. It deliberately does not compute a rate: the denominator
everybody means by "churn rate" differs by company, and guessing which one
you meant would produce a number you could not defend.

Place it beside
[new subscribers](/sources/stripe/new-subscribers) and
[active subscribers](/sources/stripe/active-subscribers), and the three
together say which direction the business is going.
[Download Notch Metrics](/download).
