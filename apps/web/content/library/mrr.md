---
title: "What is MRR?"
description: "Monthly recurring revenue, what it includes, how to normalise annual and weekly plans, and why two correct MRR figures can disagree."
date: 2026-10-11
author: Notch Metrics
tags: [mrr, glossary, saas]
kind: glossary
term: Monthly recurring revenue
faq:
  - question: What does MRR stand for?
    answer: >-
      Monthly recurring revenue. It is the value of your active subscriptions
      normalised to one month, as a snapshot of the book right now rather than a
      total of what arrived recently.
  - question: How do you convert an annual plan to MRR?
    answer: >-
      Divide by twelve. An annual plan at $1,188 contributes $99 of MRR. A
      quarterly plan is divided by three, and a weekly plan is multiplied by 52
      and divided by 12, because a month averages 4.345 weeks rather than four.
  - question: Is MRR the same as last month's revenue?
    answer: >-
      No. A month with many annual renewals brings in a lot of cash without
      changing MRR, because the book did not grow. MRR is what you are owed per
      month right now; revenue is what arrived in a window.
  - question: Why do two tools report different MRR for the same account?
    answer: >-
      Because each makes choices about trials, past-due subscriptions,
      discounts, tax and usage-based prices. None of those has a single right
      answer. What matters is writing your definition down and keeping it.
  - question: Should trials count towards MRR?
    answer: >-
      Usually not. A trial is revenue nobody has agreed to pay yet, so most
      providers and tools exclude them. Lemon Squeezy's own active subscriber
      count is a notable exception that counts trials in.
---

**Monthly recurring revenue is the value of your active subscriptions,
normalised to one month.** It is a snapshot of the book as it stands, not a
total of what arrived in the last thirty days.

## How MRR is calculated

Take every active subscription, convert its price to a monthly amount, and
add them up.

| Billing interval | Monthly contribution                |
| ---------------- | ----------------------------------- |
| Monthly          | The amount                          |
| Annual           | Divided by twelve                   |
| Quarterly        | Divided by three                    |
| Weekly           | Multiplied by 52, divided by 12     |
| Daily            | Multiplied by 365.25, divided by 12 |

The weekly row is the one people get wrong. A month is 4.345 weeks on
average, not four, so multiplying a weekly price by four undercounts it by
about eight per cent.

## What MRR is not

**Not last month's revenue.** A month with many annual renewals brings in
enormous cash and does not change MRR at all, because the book did not grow.

**Not a sum over a window.** MRR is what you are owed per month right now.
Asking for "MRR over the last 90 days" is asking a question with no answer.

**Not ARR divided by anything other than twelve.** ARR is MRR times twelve,
by definition. Anything smoothed or annualised differently is a forecast
wearing a metric's name.

## Why two MRR figures disagree

Every provider and every tool makes a handful of choices, and every choice
moves the number a per cent or two.

- **Trials.** Counted, or not? Most exclude them, because a trial is revenue
  nobody has agreed to.
- **Past due.** A card is failing and dunning is retrying. Still revenue, or
  already lost?
- **Discounts.** Percentage coupons usually applied. Fixed-amount coupons
  often not, because prorating one across a multi-item subscription needs
  data most APIs do not return.
- **Tax.** A merchant of record collects VAT that is not yours. Including it
  inflates MRR by whatever your customers' rates average.
- **Usage-based prices.** Not priceable in advance. Guessed, or flagged?

None of these has a right answer. What matters is writing yours down, keeping
it, and being able to say what your figure counts when somebody asks.

## MRR in Notch Metrics

Seven connectors report it, each using their provider's own definition where
one exists:
[Stripe](/sources/stripe/mrr), [Polar](/sources/polar/mrr),
[Paddle](/sources/paddle/mrr),
[Dodo Payments](/sources/dodopayments/mrr),
[Lemon Squeezy](/sources/lemonsqueezy/mrr) and
[RevenueCat](/sources/revenuecat/mrr).

Each page states exactly what that provider's figure includes, because MRR is
always somebody's definition and the whole point is knowing whose.

[How to calculate MRR from the Stripe API](/blog/calculate-mrr-from-the-stripe-api)
