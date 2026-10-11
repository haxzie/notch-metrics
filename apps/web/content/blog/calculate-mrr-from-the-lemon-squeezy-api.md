---
title: "How to calculate MRR from the Lemon Squeezy API"
description: "Subscriptions, variants and renewal intervals. How to compute Lemon Squeezy MRR, and the JSON:API shape that catches people out."
date: 2026-10-11
author: Notch Metrics
tags: [lemonsqueezy, mrr, api]
pillar: lemon-squeezy-mrr-on-your-mac
faq:
  - question: Why are my Lemon Squeezy API fields undefined?
    answer: >-
      Because Lemon Squeezy serves JSON:API. The fields live on attributes
      rather than on the object itself, so sub.status is undefined and
      sub.attributes.status is the value. Set Accept and Content-Type to
      application/vnd.api+json as well.
  - question: Where is the price on a Lemon Squeezy subscription?
    answer: >-
      Not on the subscription. A subscription carries a variant_id and the price
      lives on the variant, so computing MRR means fetching each distinct
      variant's price and joining. Deduplicate the lookups or a thousand
      subscribers becomes a thousand calls.
  - question: What is renewal_interval_quantity in Lemon Squeezy?
    answer: >-
      The multiplier on the interval unit. A price renewing every six months has
      a unit of month and a quantity of six, so its monthly value is the amount
      divided by six. Annual plans have a quantity of one and hide the bug.
  - question: Should on_trial Lemon Squeezy subscriptions count towards MRR?
    answer: >-
      Usually not, because a trial is revenue nobody has agreed to yet. Note
      that this differs from Lemon Squeezy's own active subscriber count, which
      counts trials in, so pick a definition and say which one you are
      reporting.
  - question: Does a cancelled Lemon Squeezy subscription still pay?
    answer: >-
      Yes, until ends_at. Whether it belongs in MRR depends on whether you are
      measuring money arriving or the book you expect to keep next month.
---

## Does Lemon Squeezy return MRR?

No. You compute it from `/v1/subscriptions`, and the first obstacle is not
the maths.

## JSON:API, and where the data actually is

Lemon Squeezy serves JSON:API. That means the fields you want are not on the
object, they are on `attributes`, and the relationships you want are
references rather than embedded objects.

```json
{
  "data": [
    {
      "type": "subscriptions",
      "id": "123",
      "attributes": { "status": "active", "variant_id": 456 },
      "relationships": { ... }
    }
  ]
}
```

Code written against a normal REST API reads `sub.status` and gets
`undefined`, every time, silently. It is `sub.attributes.status`.

Set the headers or you get nothing useful back:

```
Accept: application/vnd.api+json
Content-Type: application/vnd.api+json
Authorization: Bearer <api key>
```

## The price is not on the subscription

This is the part that makes Lemon Squeezy MRR more work than it looks. A
subscription carries a `variant_id`, and the price lives on the variant, not
on the subscription.

So the calculation is two passes. Collect the distinct variant ids from your
active subscriptions, fetch each one's price once, then sum.

```js
const PER_MONTH = { day: 365 / 12, week: 52 / 12, month: 1, year: 1 / 12 };

async function mrr(key, storeId) {
  const subs = await list(
    key,
    `/v1/subscriptions?filter[store_id]=${storeId}&filter[status]=active`,
  );

  // Fetch each price once, not once per subscriber.
  const variantIds = [...new Set(subs.map((s) => s.attributes.variant_id))];
  const prices = new Map();
  for (const id of variantIds) {
    const price = await fetchPriceForVariant(key, id);
    prices.set(id, price);
  }

  let total = 0;
  for (const sub of subs) {
    const price = prices.get(sub.attributes.variant_id);
    if (!price) continue;

    const per = PER_MONTH[price.renewal_interval_unit] ?? 0;
    total += (price.unit_price * per) / (price.renewal_interval_quantity ?? 1);
  }

  return Math.round(total);
}
```

Deduplicating the variant lookups matters. A thousand subscribers across six
plans is six price calls, not a thousand, and the difference is whether you
stay inside the rate limit.

## renewal_interval_quantity

Same trap as everywhere else. A price renewing every six months has
`renewal_interval_unit` of `month` and `renewal_interval_quantity` of 6, so
its monthly value is the amount divided by six.

Annual plans have a quantity of one and look correct without it, which is why
the bug survives until somebody sells a six-monthly plan.

## Statuses, and the trial question

Lemon Squeezy subscriptions can be `on_trial`, `active`, `paused`,
`past_due`, `unpaid`, `cancelled` or `expired`.

Filtering on `active` excludes trials, which is the honest basis for MRR.
Note that this differs from Lemon Squeezy's own active subscriber count,
which counts trials in. Two reasonable definitions, and you have to pick
which one you are reporting and say so.

`cancelled` is worth a second look: a cancelled Lemon Squeezy subscription
keeps running until `ends_at`, so it is still being paid for. Whether it
belongs in MRR depends on whether you are measuring money arriving or the
book you expect to keep.

## Pagination

`page[size]` up to 100, and `links.next` to continue. Page until there is no
next link.

## Or read it off the notch

Notch Metrics computes [Lemon Squeezy MRR](/sources/lemonsqueezy/mrr) this
way, caching the variant prices, and shows it in the MacBook notch alongside
[revenue](/sources/lemonsqueezy/revenue),
[active subscribers](/sources/lemonsqueezy/active-subscribers),
[refunds](/sources/lemonsqueezy/refunds) and a feed of
[recent orders](/sources/lemonsqueezy/recent-payments).

[Everything Lemon Squeezy reports](/sources/lemonsqueezy), or
[download Notch Metrics](/download).
