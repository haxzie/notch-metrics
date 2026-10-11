---
title: "How to separate one-time sales from subscriptions in Dodo Payments"
description: "A single revenue total hides the shape of the business. How to split recurring from one-off in Dodo Payments, and why it matters."
date: 2026-10-11
author: Notch Metrics
tags: [dodopayments, revenue, api]
pillar: dodo-payments-revenue-in-the-notch
faq:
  - question: How do I tell a Dodo Payments subscription renewal from a one-time sale?
    answer: >-
      A payment tied to a subscription carries a subscription id and a one-off
      purchase does not. Filtering on the presence of that field is the whole
      mechanism.
  - question: Is the first invoice of a subscription a one-time sale?
    answer: >-
      No. It carries a subscription id, so it belongs to recurring revenue.
      Classifying by product rather than by subscription id gets this wrong in
      the most flattering direction, because launch months then look better than
      they were.
  - question: Is recurring revenue the same as MRR?
    answer: >-
      No. Recurring revenue in a window is what renewals actually charged in
      those days. MRR is the normalised monthly value of the book as it stands,
      with annual plans divided by twelve. A month full of annual renewals shows
      huge recurring revenue and unchanged MRR.
  - question: Why does splitting one-time sales from subscriptions matter?
    answer: >-
      Because a flat total can hide a business losing subscriptions and covering
      the gap with launches. Recurring revenue carries into next month on its
      own. A one-time sale has to be earned again.
  - question: Can Notch Metrics show both halves at once?
    answer: >-
      Yes. Total revenue and one-time sales are separate widgets, and MRR sits
      beside them. Place all three in the notch and the shape of the month is
      legible at a glance.
---

## Why split revenue at all?

Because recurring revenue and one-time sales are different assets, and a
single total treats them as the same money.

Recurring revenue is a book. It carries into next month without anybody doing
anything. A one-time sale is finished the moment it lands: next month starts
at zero again.

A business whose total revenue is flat for three months might be perfectly
healthy, or it might be losing subscriptions and covering the gap with
launches. The total cannot tell you which. The split can.

## How Dodo Payments distinguishes them

A payment tied to a subscription carries a subscription id. A one-off
purchase does not.

```js
const succeeded = payments.filter((p) => p.status === "succeeded");

const recurring = succeeded.filter((p) => p.subscription_id);
const oneTime = succeeded.filter((p) => !p.subscription_id);

const sum = (rows) => rows.reduce((total, p) => total + p.total_amount, 0);
```

That is the whole mechanism. It is simple enough that the interesting part is
the edge cases.

## The first invoice is recurring

When somebody subscribes, the first charge looks exactly like a one-off
purchase on the day it happens. A single payment, a single product, a card
charged once.

It is not. It carries a subscription id, so the filter above puts it in the
right bucket, and that is correct: the first invoice of a subscription is the
start of a book, not a sale that is over.

Code that classifies by product rather than by subscription id gets this
wrong, and gets it wrong in the most flattering direction, because launch
months look better when every new subscriber counts as a one-time sale.

## MRR is not the recurring half of revenue

Two different numbers, and conflating them is the common mistake.

Recurring revenue in a window is what renewals actually charged in those
days. MRR is the normalised monthly value of the book as it stands right now,
including annual plans divided by twelve.

A month with many annual renewals shows enormous recurring revenue and
unchanged MRR. Both figures are correct. They answer different questions:
recurring revenue is cash that arrived, MRR is what the book is worth.

## What to watch

Three ratios are worth more than any one of these figures alone.

**One-time share of total.** If it climbs, the business is becoming
launch-driven, and launch-driven businesses have to keep launching.

**Recurring revenue against MRR.** If recurring revenue is well above
one twelfth of ARR, you are collecting annual plans, which is good for cash
and means churn will be invisible for a year.

**One-time sales against new subscriptions.** One-time buyers who never
subscribe are a different audience, and worth knowing about before you build
only for the subscribers.

## In the notch

Notch Metrics reports both halves as separate widgets.
[Total revenue](/sources/dodopayments/revenue) counts every succeeded payment
in the window, renewals and one-off purchases together.
[One-time sales](/sources/dodopayments/one-time-sales) counts only the
payments not tied to a subscription. Both gross, before refunds and fees.

[MRR](/sources/dodopayments/mrr) sits beside them as a snapshot of the book,
so the three together say what kind of business you are running this month.

[Everything Dodo Payments reports](/sources/dodopayments), or
[download Notch Metrics](/download).
