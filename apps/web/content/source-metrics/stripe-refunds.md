---
lede: >-
  Refunds are reported as their own number rather than being quietly subtracted from revenue.
---

## Why refunds are not netted off

Gross revenue with refunds already removed hides the thing you need to see. A
month that takes fifteen thousand and refunds three is a different business
from a month that takes twelve and refunds none, and a single net figure
calls them identical.

Notch Metrics reads refund balance transactions in the window and reports the
total as a positive amount. Place it beside the revenue widget and the pair
tells you what you kept.

## Refunds are not chargebacks

A refund is money you chose to return. A chargeback is money a card network
took back, and it costs a dispute fee on top. Stripe records them as
different balance transaction types and only refunds are counted here.

Refunds are bucketed by when the refund was processed, not by when the
original charge was taken. A refund on a charge from three months ago lands
in this week.
