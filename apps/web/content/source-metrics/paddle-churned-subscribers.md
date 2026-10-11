---
lede: >-
  Churned subscriptions are Paddle subscriptions that ended in the window, and Paddle's status model has more than one way to get there.
---

## Cancelled, paused and past due

Paddle subscriptions move between `active`, `trialing`, `paused`,
`past_due` and `canceled`. Only `canceled` is counted here. A paused
subscription is not churn: the customer intends to come back and Paddle will
resume billing. A past-due one is a failed payment in retry, and treating it
as churn would double count when it either recovers or cancels for real.

That distinction matters more on Paddle than on most providers, because
dunning runs for a while before a subscription is finally cancelled. Your
churn figure therefore lags the payment failure that caused it.

## A count, not a rate

This is subscriptions lost, not a percentage. Put it beside new subscriptions
to read net movement, and beside MRR to see whether the ones you lost were
the ones that mattered.
