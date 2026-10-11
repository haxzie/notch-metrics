---
title: "How to pull Lemon Squeezy revenue and refunds by store"
description: "Orders, totals and the refund date the API will not give you. How to sum Lemon Squeezy revenue per store, and what the numbers leave out."
date: 2026-10-11
author: Notch Metrics
tags: [lemonsqueezy, revenue, api]
pillar: lemon-squeezy-mrr-on-your-mac
faq:
  - question: How do I filter Lemon Squeezy orders by store?
    answer: >-
      Pass filter[store_id] on the orders endpoint. One account can hold several
      stores and the API returns all of them by default, so without the filter
      you are summing a business you may not have meant to include.
  - question: Should refunded orders count in Lemon Squeezy revenue?
    answer: >-
      Yes, in a gross figure, on the day they were paid. Report refunds as a
      separate number. Excluding refunded orders from revenue and also reporting
      refunds separately counts the refund twice.
  - question: Does Lemon Squeezy order total include tax?
    answer: >-
      Yes. total is what the customer paid, including tax that Lemon Squeezy
      collected as merchant of record and will remit. Use subtotal if you want
      the figure before tax and discounts.
  - question: Can I get Lemon Squeezy refunds by refund date?
    answer: >-
      Not from the orders list. refunded_amount sits on the order and there is
      no way to filter or bucket by when the refund occurred, so a refunds
      series is bucketed by order date. Listen for the order_refunded webhook to
      record the real date.
  - question: How does pagination work on the Lemon Squeezy API?
    answer: >-
      page[size] up to 100, with a links.next URL to continue. Follow the next
      link rather than rebuilding the URL, because it already carries your
      filters and a hand-built page two is how a store filter gets dropped.
---

## Where does Lemon Squeezy revenue come from?

The orders list, filtered to your store.

```bash
curl -s 'https://api.lemonsqueezy.com/v1/orders?filter[store_id]=12345&page[size]=100' \
  -H 'Accept: application/vnd.api+json' \
  -H 'Authorization: Bearer <api key>'
```

One account can hold several stores and the API returns all of them by
default, so the `filter[store_id]` is not optional in practice. Without it
you are summing a business you may not have meant to include.

## Which orders took money

An order's `attributes.status` tells you. `paid` is money. `pending` has not
completed, `failed` did not, and `refunded` did take money and then gave it
back, which means it still belongs in your gross figure for the day it
happened.

```js
const paid = orders.filter((o) => ["paid", "refunded"].includes(o.attributes.status));
const gross = paid.reduce((sum, o) => sum + o.attributes.total, 0);
```

Excluding refunded orders from revenue and also reporting refunds separately
double counts the refund. Pick gross plus a separate refund figure, which is
the convention everybody expects.

## What total actually is

`attributes.total` is in minor units of `attributes.currency`, and Lemon
Squeezy gives you several totals on the same order:

| Field             | What it holds            |
| ----------------- | ------------------------ |
| `subtotal`        | Before tax and discounts |
| `discount_total`  | What a coupon took off   |
| `tax`             | Collected on your behalf |
| `total`           | What the customer paid   |
| `refunded_amount` | What has been given back |

Lemon Squeezy is a merchant of record, so `tax` is not yours. A `total`
compared against a Stripe gross figure overstates the Lemon Squeezy side by
roughly the tax rate.

There is also `total_usd` and friends, which are Lemon Squeezy's own
conversion. Useful for a multi-currency store, and worth noting in your chart
that a conversion happened.

## The refund date does not exist

This is the real limitation. `refunded_amount` sits on the order, and so does
`refunded_at` on some payloads, but the orders list gives you no way to
filter or bucket by when the refund occurred.

So a refunds series built from the orders list is bucketed by the order date,
not the refund date. A refund processed this week on an order from March
appears in March, and your current week shows nothing.

That is a real constraint rather than an implementation choice, and the only
way around it is to listen for the `order_refunded` webhook and record the
date yourself.

## Pagination

```js
async function orders(key, storeId) {
  const rows = [];
  let url = `https://api.lemonsqueezy.com/v1/orders?filter[store_id]=${storeId}&page[size]=100`;

  while (url) {
    const res = await fetch(url, {
      headers: { Accept: "application/vnd.api+json", Authorization: `Bearer ${key}` },
    });
    const body = await res.json();
    rows.push(...body.data);
    url = body.links?.next ?? null;
  }

  return rows;
}
```

The `next` link carries your filters already. Rebuilding the URL by hand is
how a store filter gets dropped on page two.

## In the notch

Notch Metrics reports [Lemon Squeezy revenue](/sources/lemonsqueezy/revenue)
as orders in the window that took payment, by `total`, gross: a later refund
does not remove the order from the day it was paid.

[Refunds](/sources/lemonsqueezy/refunds) are a separate widget, and the page
says plainly that they are bucketed by the order date rather than the refund
date, because the API does not expose the latter. A number whose limits are
hidden is a number you cannot use.

[Everything Lemon Squeezy reports](/sources/lemonsqueezy), or
[download Notch Metrics](/download).
