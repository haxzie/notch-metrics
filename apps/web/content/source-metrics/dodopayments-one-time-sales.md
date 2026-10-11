---
lede: >-
  One-time sales are purchases that are not subscriptions, kept separate from recurring revenue on purpose.
---

## Why the split matters

A month where total revenue held steady can hide a collapse in subscriptions
covered by a good week of one-off sales. The two behave completely
differently: recurring revenue is a book that carries into next month, and a
one-time sale is money that has to be earned again.

Dodo Payments records both. This widget counts the non-recurring payments in
the window, and the MRR widget reports the recurring book. Place them side by
side and the shape of the business is legible at a glance.

## What is counted

Successful one-time payments in the window, bucketed by payment time, before
fees. Refunds are not netted off. Amounts are integer minor units with an ISO
4217 code, reported in your Dodo Payments account's currency.

A subscription's first invoice is recurring revenue, not a one-time sale,
even though it looks like a single payment on the day it is taken.
