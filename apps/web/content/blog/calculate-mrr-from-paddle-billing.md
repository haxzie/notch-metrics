---
title: "How to calculate MRR from Paddle Billing"
description: "Paddle Billing has no MRR endpoint. Here is how to compute it from the subscriptions list, including the billing cycle maths most people get wrong."
date: 2026-10-11
author: Notch Metrics
tags: [paddle, mrr, api]
pillar: paddle-mrr-on-your-mac
faq:
  - question: Does Paddle Billing have an MRR API endpoint?
    answer: >-
      No. The Paddle dashboard shows MRR but the API does not return one. You
      compute it from the subscriptions list by normalising each recurring item
      to a monthly amount.
  - question: Why are Paddle amounts returned as strings?
    answer: >-
      Paddle serialises money as a string of minor units, such as "1900", to
      avoid float precision problems in JSON. Convert with Number() before
      arithmetic, or adding two amounts concatenates them.
  - question: What does frequency mean on a Paddle billing cycle?
    answer: >-
      It is the multiplier on the interval. A price billing every three months
      has interval month and frequency 3, so its monthly contribution is the
      amount divided by three. Ignoring frequency makes quarterly plans read as
      three times their worth.
  - question: Should past_due Paddle subscriptions count towards MRR?
    answer: >-
      It is a judgement call. The customer still intends to pay and dunning is
      running, so including them overstates slightly and excluding them makes
      MRR drop on a card expiry that will probably resolve. Excluding is the
      safer default.
  - question: Does Paddle apply discounts to the subscription item price?
    answer: >-
      No. Paddle applies discounts at billing time rather than storing a reduced
      price, so an MRR computed from item prices is list price. A customer on a
      permanent discount contributes more than they actually pay.
---

## Does Paddle Billing have an MRR endpoint?

No. Paddle's dashboard shows MRR; its API does not return one. You compute it
from `/subscriptions`, and the structure of a Paddle subscription makes that
slightly more work than it looks.

This is Paddle Billing, the current API at `api.paddle.com`. Paddle Classic
was a different product with a different API and none of this applies to it.

## The shape of a Paddle subscription

A subscription has an `items` array. Each item has a `price`, and each price
has a `billing_cycle` with an `interval` and a `frequency`. The frequency is
the multiplier: a price billing every three months has `interval: "month"`
and `frequency: 3`.

An item can also be non-recurring, in which case `billing_cycle` is null and
it is a one-off charge sitting on a subscription. Those must not count
towards MRR.

```js
const PER_MONTH = { day: 365 / 12, week: 52 / 12, month: 1, year: 1 / 12 };

function subscriptionMrr(sub) {
  let total = 0;

  for (const item of sub.items) {
    const cycle = item.price?.billing_cycle;
    // A one-off charge on a subscription. Not recurring revenue.
    if (!cycle) continue;

    const unit = Number(item.price.unit_price.amount); // minor units, as a string
    const amount = unit * (item.quantity ?? 1);

    total += (amount * PER_MONTH[cycle.interval]) / cycle.frequency;
  }

  return total;
}
```

Two details in there cost people an afternoon each.

**Amounts are strings.** Paddle returns `unit_price.amount` as a string of
minor units, `"1900"` rather than `1900`. Add two of them without converting
and you get `"19001900"`. `Number()` them on the way in.

**Divide by `frequency`.** A quarterly price is `month` with frequency 3, so
the monthly figure is the amount divided by three. Treating frequency as
decoration makes quarterly plans read as three times their worth, and
annual-with-frequency-1 plans read fine, so the bug hides until somebody buys
quarterly.

## Which statuses to include

Paddle subscriptions are `active`, `trialing`, `paused`, `past_due` or
`canceled`.

Count `active`. Do not count `trialing`, which is revenue nobody has agreed
to. Do not count `paused`, which is revenue explicitly suspended. `past_due`
is a judgement call: the customer still intends to pay and dunning is
running, so including it overstates slightly and excluding it makes your MRR
drop on a card expiry that will probably resolve. Excluding it is the safer
default.

```js
const res = await fetch("https://api.paddle.com/subscriptions?status=active&per_page=100", {
  headers: { Authorization: `Bearer ${apiKey}` },
});
```

## Discounts are not applied

Paddle applies discounts at billing time rather than storing a reduced price
on the item. So the calculation above is list price, and a customer on a
permanent 20% discount contributes more MRR here than they actually pay.

Fixing that means reading the subscription's `discount`, looking up the
discount object, and applying it, which is another call per distinct
discount. Whether that is worth it depends on how much of your book is
discounted. Either way, know which one your figure is and say so.

## Pagination

Paddle pages with `per_page` and a cursor in `meta.pagination.next`. Page
until there is no next link rather than until you see a short page: Paddle
can return a short page with more to come.

## Or read it off the notch

Notch Metrics computes [Paddle MRR](/sources/paddle/mrr) this way, on its own
schedule, and shows it in the MacBook notch. Active subscriptions, each
recurring item's unit price times quantity normalised to a month by its
billing cycle, discounts not applied, as a snapshot of the book right now.
The definition is written on the page so nobody has to read the code.

Connect Paddle once on the web.
[Everything Paddle reports](/sources/paddle), or
[download Notch Metrics](/download).
