---
title: "How to calculate MRR from the Stripe API"
description: "Stripe has no MRR endpoint. Here is how to compute it from the subscriptions list, and why your number will not match the one in Stripe Billing."
date: 2026-10-11
author: Notch Metrics
tags: [stripe, mrr, api]
pillar: stripe-mrr-on-your-mac
faq:
  - question: Does the Stripe API have an MRR endpoint?
    answer: >-
      No. Stripe Billing shows MRR in its own analytics, but no API returns it.
      You compute MRR by listing active subscriptions and normalising each line
      item to a monthly amount.
  - question: How do you convert an annual Stripe plan to MRR?
    answer: >-
      Divide the annual amount by twelve. An annual plan at $1,188 contributes
      $99 of MRR. For weekly plans, multiply by 52 and divide by 12 rather than
      by four, because a month is not four weeks.
  - question: Why does my calculated Stripe MRR not match Stripe Billing?
    answer: >-
      Stripe Billing normalises differently in places, treats tax differently
      depending on whether your prices are inclusive, and updates on its own
      schedule. A few per cent of disagreement is normal. What matters is that
      your figure is consistent and that you can say what it counts.
  - question: Should trialing subscriptions count towards Stripe MRR?
    answer: >-
      Usually not. A trialing subscription is revenue nobody has agreed to pay
      yet. Filter the subscriptions list to status active, which excludes
      trialing, past_due, unpaid, paused and canceled.
  - question: Do Stripe coupons reduce MRR?
    answer: >-
      Yes, and they sit in two places. A discount can be on the subscription or
      on an individual line item, and both apply. A percentage coupon scales the
      amount, a fixed-amount coupon subtracts from it with a floor of zero, and
      a repeating coupon stops applying after its duration.
  - question: How do I avoid Stripe rate limits when calculating MRR?
    answer: >-
      Cache the result. The subscriptions list pages at 100, so twenty thousand
      subscriptions means two hundred calls for one number. MRR moves slowly, so
      recomputing it every minute buys nothing.
---

## Does Stripe have an MRR endpoint?

No. Stripe Billing shows an MRR figure in its own analytics, but there is no
API that returns it. If you want MRR programmatically you compute it from the
subscriptions list, and the moment you do you have to decide what you mean by
it.

That is the real difficulty. MRR is always somebody's definition. Gross or
net of discounts, trials counted or not, tax included or not. Stripe picked
one, you will pick another, and the two will differ by a few per cent
forever.

## The calculation

Walk every active subscription, normalise each line item to a month, and sum.

```js
const SECONDS_PER_MONTH = { day: 1 / 30.4375, week: 12 / 52, month: 1, year: 1 / 12 };

async function mrr(stripe) {
  let total = 0;

  for await (const sub of stripe.subscriptions.list({
    status: "active",
    limit: 100,
    expand: ["data.discounts"],
  })) {
    for (const item of sub.items.data) {
      const price = item.price;
      if (!price.recurring) continue;

      // Minor units. Never a float.
      const amount = (price.unit_amount ?? 0) * (item.quantity ?? 1);
      const perMonth =
        (amount * SECONDS_PER_MONTH[price.recurring.interval]) /
        (price.recurring.interval_count ?? 1);

      total += perMonth;
    }
  }

  return Math.round(total);
}
```

Four things in that snippet are the whole job.

**`status: "active"`.** Stripe subscriptions can be `trialing`, `past_due`,
`unpaid`, `paused`, `canceled` or `incomplete`. Only `active` is money you
are currently being paid. Including `trialing` counts revenue nobody has
agreed to yet, and including `past_due` counts revenue that is failing.

**Line items, not the subscription.** A subscription has an `items` array and
each item has its own price, interval and quantity. A plan with a base fee
and a per-seat add-on is two items, and reading only the first one
undercounts every customer you have.

**Annual divided by twelve.** An annual plan at $1,188 is $99 of MRR, not
$1,188. Weekly plans are the awkward ones: multiply by 52 and divide by 12,
not by four, because a month is not four weeks.

**`interval_count`.** A price can bill every three months. Its interval is
`month` and its `interval_count` is 3, so the monthly figure is the amount
divided by three. Miss this and quarterly plans read as three times their
worth.

## Discounts, which is where numbers diverge

A percentage coupon reduces MRR. A fixed-amount coupon reduces it by the
amount, floored at zero. A coupon with a `duration` of `repeating` reduces it
only for the months it runs, which means your MRR will step up on a date
nobody wrote down.

```js
function applyDiscount(amount, discounts) {
  for (const discount of discounts ?? []) {
    const coupon = discount.coupon;
    if (coupon?.percent_off) amount -= amount * (coupon.percent_off / 100);
    if (coupon?.amount_off) amount = Math.max(0, amount - coupon.amount_off);
  }
  return amount;
}
```

Discounts sit in two places: on the subscription and on the individual item.
Both apply, and an implementation that reads only the subscription one
reports too high for anybody on a line-item discount.

## Why your number will not match Stripe's

Stripe Billing's own MRR normalises differently in places, handles tax
differently depending on whether your prices are inclusive, and has its own
view of when a subscription starts counting. It also updates on its own
schedule rather than at the moment a subscription changes.

A few per cent of disagreement is normal. What matters is that your figure is
consistent with itself over time, and that you can say exactly what it counts
when somebody asks. Write the definition down next to the code.

## Pagination, and the part that bites in production

`stripe.subscriptions.list` is paginated at 100. The auto-pagination above
handles it, but a business with twenty thousand subscriptions makes two
hundred API calls every time you want one number. You will hit rate limits,
and you will hit them at the worst moment.

Cache the result. MRR is a snapshot that moves slowly, and recomputing it
every minute buys nothing.

## Or skip the whole thing

Notch Metrics computes Stripe MRR on its own schedule and puts it in the
MacBook notch. Active subscriptions, each item normalised to a month, annual
divided by twelve, weekly times 52 over 12, reduced by percentage coupons. A
snapshot, not a sum over the window, and the definition is written on
[the MRR page](/sources/stripe/mrr) so you never have to guess what it
counts.

Connect Stripe once with a read-only restricted key, place the widget, and
the number is there every time you glance up.
[Download it](/download), or read what else
[the Stripe connector reports](/sources/stripe).
