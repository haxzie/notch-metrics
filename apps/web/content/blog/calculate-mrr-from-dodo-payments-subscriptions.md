---
title: "How to calculate MRR from Dodo Payments subscriptions"
description: "Dodo Payments has no MRR endpoint. Compute it from active subscriptions, normalising each pre-tax recurring amount by its payment frequency."
date: 2026-10-11
author: Notch Metrics
tags: [dodopayments, mrr, api]
pillar: dodo-payments-revenue-in-the-notch
faq:
  - question: Does the Dodo Payments API return MRR?
    answer: >-
      No. There is no MRR endpoint. You compute it by listing active
      subscriptions and normalising each recurring_pre_tax_amount to a monthly
      figure using its payment frequency.
  - question: Why does Dodo Payments MRR use a pre-tax amount?
    answer: >-
      Because the VAT a merchant of record collects is not your revenue.
      Including it would inflate MRR by whatever your customers' tax rates
      average, and it is usually the whole gap when a merchant-of-record MRR
      looks higher than an equivalent Stripe one.
  - question: What is payment_frequency_count in Dodo Payments?
    answer: >-
      The multiplier on the interval. A subscription billing every three months
      has an interval of month and a count of three, so its monthly contribution
      is the amount divided by three. Ignoring the count makes quarterly plans
      read as three times their worth.
  - question: How do you convert a weekly subscription to MRR?
    answer: >-
      Multiply by 52 and divide by 12. A month averages 4.345 weeks, so treating
      a month as four weeks undercounts weekly plans by about eight per cent.
  - question: Why does the MRR widget have no sparkline?
    answer: >-
      Because MRR is the value of the book right now, not a total over a window.
      A daily MRR series built from a single current snapshot would be invented
      data rather than anything the API returned.
---

## Does Dodo Payments return MRR?

No. There is no MRR endpoint, so you compute it from the subscriptions list.

The good news is that Dodo Payments gives you the right field to do it with,
which is more than most merchants of record manage.

## The field that matters

`recurring_pre_tax_amount`, and both halves of that name are the point.

**Recurring.** It is the amount that repeats, not the amount of the next
invoice, which may include a prorated change or a one-off add-on.

**Pre-tax.** Tax is excluded. That is the correct basis for MRR: the VAT a
merchant of record collects is not your revenue, so including it would
inflate the figure by whatever your customers' tax rates happen to average.

If you have ever compared a merchant-of-record MRR against a Stripe MRR and
found it mysteriously higher, tax is usually the whole gap.

## The calculation

```js
const PER_MONTH = { daily: 365 / 12, weekly: 52 / 12, monthly: 1, yearly: 1 / 12 };

async function mrr(key, host) {
  const subs = await listSubscriptions(key, host, { status: "active" });

  let total = 0;
  for (const sub of subs) {
    const amount = sub.recurring_pre_tax_amount; // minor units
    const per = PER_MONTH[sub.payment_frequency_interval?.toLowerCase()] ?? 0;
    // The count is the multiplier: every 3 months is monthly / 3.
    total += (amount * per) / (sub.payment_frequency_count ?? 1);
  }

  return Math.round(total);
}
```

`payment_frequency_interval` and `payment_frequency_count` work together. A
subscription billing every three months has an interval of month and a count
of three, so its monthly contribution is the amount divided by three.

Treating the count as decoration is the bug that hides, because annual plans
have a count of one and look fine, and quarterly plans quietly read as three
times their worth until somebody checks.

## Weekly plans, and the month that is not four weeks

Multiply a weekly amount by 52 and divide by 12, not by four. A month
averages 4.345 weeks, so the four-week shortcut undercounts weekly plans by
about eight per cent. Few businesses have many weekly subscriptions, and the
ones that do are usually the ones who notice.

## Which statuses count

`active`. A subscription that is cancelled, expired or on hold is not paying
you this month, and including it reports a book you no longer have.

Trials are the judgement call, as always. A trial is revenue nobody has
agreed to yet. Excluding it is the honest default and it is what Notch
Metrics does.

## A snapshot, not a sum

MRR is the value of the book right now. It is not a total over a window, and
a sparkline of it is a sparkline of your own history rather than of anything
the API returned.

That is why the widget shows the figure without one. A chart implying a daily
MRR series built from a single current snapshot would be inventing data.

## Or read it off the notch

Notch Metrics computes [Dodo Payments MRR](/sources/dodopayments/mrr) exactly
this way: active subscriptions, each `recurring_pre_tax_amount` normalised to
a monthly amount using its payment frequency, as a snapshot of the book right
now.

Put it beside [total revenue](/sources/dodopayments/revenue) and
[one-time sales](/sources/dodopayments/one-time-sales) and the month reads at
a glance. [Everything Dodo Payments reports](/sources/dodopayments), or
[download Notch Metrics](/download).
