---
title: "What is churn rate?"
description: "Churn is the customers or revenue you lose in a period. Why the denominator is the whole argument, and how voluntary and involuntary churn differ."
date: 2026-10-11
author: Notch Metrics
tags: [churn, glossary, saas]
kind: glossary
term: Churn rate
faq:
  - question: How do you calculate churn rate?
    answer: >-
      Divide customers lost in a period by a denominator, which is where the
      disagreement is. Customers at the start, customers at the start plus new,
      the average of start and end, and MRR at the start are all defensible and
      all give different numbers.
  - question: What is the difference between customer churn and revenue churn?
    answer: >-
      Customer churn counts people and revenue churn counts money, and they can
      point in opposite directions. Losing ten customers on your cheapest plan
      is high customer churn; losing one enterprise account is high revenue
      churn and barely registers in the other.
  - question: What is negative churn?
    answer: >-
      Net revenue churn below zero, which happens when expansion revenue from
      existing customers outweighs what cancellations took away. It is the shape
      every subscription business wants and most never reach.
  - question: What is involuntary churn?
    answer: >-
      Churn caused by a failed payment rather than a decision: an expired card,
      a declined bank, a retry schedule that gives up. For many businesses it is
      20% to 40% of all churn and it is mostly recoverable with better dunning.
  - question: When should a cancellation count as churn?
    answer: >-
      When the subscription actually ends, not when somebody clicks cancel. A
      subscription cancelled with the period left to run keeps paying, so
      counting it on the click makes churn spike while revenue does not move for
      a year.
---

**Churn is what you lose.** Customers who cancel, or the revenue they took
with them, over a period. Churn rate expresses that loss as a fraction of
what you had.

The count is easy. The rate is where everybody disagrees.

## The denominator is the argument

There is no single correct churn rate, because there is no agreed
denominator.

| Denominator              | What the rate then means                                           |
| ------------------------ | ------------------------------------------------------------------ |
| Customers at the start   | The classic. Ignores anybody who joined and left inside the period |
| Start plus new           | Counts fast churners. Always a lower number                        |
| Average of start and end | Smoother, harder to explain                                        |
| MRR at the start         | Revenue churn, not customer churn. A different metric              |

All four are defensible and all four give different numbers. Pick one, write
it down beside the code, and never change it quietly. A churn rate whose
definition moved is worse than no churn rate, because the trend line still
looks real.

## Customer churn against revenue churn

They answer different questions and can point in opposite directions.

**Customer churn** counts people. Losing ten customers on your cheapest plan
is a high customer churn month.

**Revenue churn** counts money. Losing one enterprise account is a high
revenue churn month and barely registers in customer churn.

**Net revenue churn** subtracts expansion revenue from existing customers.
If upgrades outweigh cancellations it goes negative, which is the shape every
subscription business wants and most never reach.

Reporting one and calling it "churn" without saying which is how two people
in the same company end up arguing about a number they both read correctly.

## Voluntary and involuntary churn

The distinction that is actually actionable.

**Voluntary churn** is somebody deciding to leave. Fixing it means fixing the
product, the price or the fit, which is slow.

**Involuntary churn** is a card expiring, a bank declining, a payment
retrying until the provider gives up. The customer never decided anything.
For many businesses it is 20% to 40% of all churn, and it is mostly
recoverable with better dunning.

They also arrive at different speeds. Involuntary churn lags the failure that
caused it by however long your retry schedule runs, so changing that schedule
moves your churn series with no change in customer behaviour at all.

## When a cancellation counts

A subscription cancelled with the period left to run is still paying. Count
it on the day somebody clicked and churn spikes while revenue does not move
for a year. Count it when the subscription actually ends and today's churn
tells you nothing about today's cancellations.

The second lines up with your active subscriber count, which is why it is the
better default.

## Churn in Notch Metrics

Three connectors report it as a count, bucketed by when the subscription
ended: [Stripe](/sources/stripe/churned-subscribers),
[Polar](/sources/polar/churned-subscribers) and
[Paddle](/sources/paddle/churned-subscribers).

A count rather than a rate, deliberately. The denominator everybody means by
"churn rate" differs by company, and guessing which one you meant would
produce a number you could not defend.

[How to measure Stripe subscriber churn](/blog/measure-stripe-subscriber-churn)
