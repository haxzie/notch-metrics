---
title: "How to get Stripe revenue for a date range with the Balance Transactions API"
description: "The charges endpoint is the wrong one. Balance transactions are what Stripe actually settles, and here is how to sum them for a window."
date: 2026-10-11
author: Notch Metrics
tags: [stripe, revenue, api]
pillar: stripe-mrr-on-your-mac
faq:
  - question: Which Stripe API endpoint returns revenue for a date range?
    answer: >-
      The balance transactions endpoint, filtered with created gte and lt and a
      type of charge. The charges endpoint misses refunds and disputes and tells
      you nothing about fees.
  - question: Does the Stripe created filter take seconds or milliseconds?
    answer: >-
      Seconds. Stripe uses Unix seconds throughout. Passing JavaScript
      milliseconds returns an empty list rather than an error, which is a common
      and quiet bug.
  - question: What is the difference between a Stripe charge and a balance transaction?
    answer: >-
      A charge is a payment intent that succeeded. A balance transaction is
      money that actually moved into your Stripe balance, carrying the amount,
      the fee and the type. Refunds, disputes and payouts exist only as balance
      transactions.
  - question: Should I report gross or net Stripe revenue?
    answer: >-
      Report gross and report refunds separately. A single net figure hides the
      difference between a month that takes fifteen thousand and refunds three
      and a month that takes twelve and refunds none.
  - question: How is money represented in the Stripe API?
    answer: >-
      Integer minor units plus an ISO 4217 currency code. Never a float. Zero-
      decimal currencies such as JPY and KRW have no minor unit, so dividing by
      a hundred is wrong for those.
  - question: Why does my Stripe API total disagree with the Stripe dashboard?
    answer: >-
      Usually timezones. The created filter is UTC and the dashboard reports in
      the timezone set on your account, so every charge near midnight lands on a
      different day. Pick one convention and write down which.
---

## Which Stripe endpoint gives revenue for a date range?

Balance transactions, not charges. Most people reach for
`/v1/charges` because it is the obvious one, and it is wrong in two ways that
only show up once real money is moving.

A charge is an intent that succeeded. A balance transaction is money that
actually arrived in your Stripe balance, and it is where fees, refunds,
disputes, payouts and adjustments all live. If you sum charges you will miss
every refund and every dispute, and you will have no idea what Stripe took.

## The call

```js
async function revenue(stripe, from, to) {
  let gross = 0;
  let fees = 0;

  for await (const txn of stripe.balanceTransactions.list({
    created: { gte: Math.floor(from / 1000), lt: Math.floor(to / 1000) },
    type: "charge",
    limit: 100,
  })) {
    gross += txn.amount;
    fees += txn.fee;
  }

  return { gross, fees, net: gross - fees };
}
```

`created` takes Unix seconds, not milliseconds, and passing milliseconds
returns an empty list rather than an error. That is thirty minutes of your
life if you have not met it before.

## The types you have to choose between

`type` is the parameter that decides what your number means.

| Type         | What it is                                                |
| ------------ | --------------------------------------------------------- |
| `charge`     | A successful payment                                      |
| `payment`    | The same thing, on accounts using certain payment methods |
| `refund`     | Money returned, as a negative amount                      |
| `adjustment` | A dispute, usually, also negative                         |
| `payout`     | Money leaving for your bank. Not revenue                  |
| `stripe_fee` | Monthly billing fees, separate from per-charge fees       |

Omitting `type` entirely sums all of them, which nets payouts against income
and produces a figure close to zero. That is a surprisingly common bug.

Note that `charge` and `payment` are different types for historical reasons
and which one your account produces depends on how the payment was taken. An
account taking both and filtering on only `charge` undercounts. Either list
both types or omit the filter and bucket by type yourself.

## Gross, net, and which one to report

A balance transaction carries `amount` and `fee`. Gross is the sum of
`amount`. Net is gross minus fees, and it is the number that arrives in your
bank.

Report gross, and report refunds separately. A single net figure hides the
thing you need to see: a month that takes fifteen thousand and refunds three
is a different business from one that takes twelve and refunds none, and
netting them calls the two identical.

## Currency, and the mistake that silently corrupts totals

Every amount is in minor units of `txn.currency`. Not dollars, cents. Not
yen-with-decimals, yen. Zero-decimal currencies like JPY and KRW have no
minor unit at all, so 1000 means 1000 yen and dividing by 100 is wrong.

Never hold money in a float. `0.1 + 0.2` is not `0.3` and a year of
summing cents into a double drifts. Integers and a currency code, always.

An account taking several currencies has several balances, and summing them
without converting produces a number that means nothing.

## Timezones

`created` is UTC. Stripe's own dashboard reports in the timezone set on your
account, so a daily figure computed in UTC will disagree with the dashboard
for every charge near midnight.

Pick one and write it down. Disagreeing with the dashboard is fine. Not
knowing why you disagree is not.

## Or let the notch do it

Notch Metrics reads balance transactions and reports Stripe revenue in the
MacBook notch, bucketed hourly, daily, weekly or monthly, with a sparkline
and a comparison against the previous window. Gross, before Stripe fees, with
[refunds reported separately](/sources/stripe/refunds) rather than netted
off.

Connect Stripe with a read-only restricted key.
[What the revenue widget counts](/sources/stripe/revenue), or
[everything else Stripe reports](/sources/stripe).
