---
title: "How to pull Polar revenue and orders by date"
description: "Two endpoints, two different numbers. When to use Polar's metrics endpoint for revenue and when to page the orders list instead."
date: 2026-10-11
author: Notch Metrics
tags: [polar, revenue, api]
pillar: polar-revenue-in-your-notch
faq:
  - question: How do I get Polar revenue for a date range?
    answer: >-
      Call GET /v1/metrics/ with start_date, end_date, interval and
      metrics=revenue. It returns order subtotals per period, before Polar's
      fees and before tax, in the organisation's currency.
  - question: Does Polar revenue include tax?
    answer: >-
      No. The revenue metric is order subtotals, which exclude tax. A business
      selling into the EU takes more at the card than this figure shows, and the
      difference is not theirs to keep.
  - question: How does pagination work on the Polar orders endpoint?
    answer: >-
      Polar pages with page and limit rather than a cursor, and the response
      carries pagination.max_page. Stop at the first page shorter than your
      limit, or read max_page.
  - question: Why do my Polar order totals disagree with the metrics endpoint?
    answer: >-
      Usually timezone. The metrics endpoint buckets in the timezone you passed
      and created_at on an order is UTC, so orders near midnight land on
      different days. Refunded orders are also counted by both on the day they
      were placed.
  - question: Can I split Polar revenue by product?
    answer: >-
      Not from the metrics endpoint. Page /v1/orders/ instead; each order
      carries the product, the subtotal, the tax and the net amount.
---

## Which Polar endpoint should you use for revenue?

Polar gives you two ways to answer "how much did we take last week" and they
are not interchangeable.

`/v1/metrics/` returns a precomputed series. `/v1/orders/` returns the orders
themselves. The first is one call and gives you a chart. The second is many
calls and gives you the rows behind it.

Use metrics for a figure. Use orders when you need to know who, or what, or
to apply a filter Polar does not offer.

## Revenue from the metrics endpoint

```bash
curl -s 'https://api.polar.sh/v1/metrics/?start_date=2026-10-01&end_date=2026-10-08&interval=day&metrics=revenue&timezone=Europe/London' \
  -H 'Authorization: Bearer polar_oat_...'
```

What comes back is order subtotals in each period, before Polar's fees and
before tax, in the organisation's currency.

Three words in that sentence matter.

**Subtotals.** Tax is excluded. A business selling to the EU takes
considerably more at the card than this figure shows, and the difference is
not yours to keep.

**Before fees.** This is gross. What lands in your bank is less Polar's
cut, and that is a separate calculation.

**The organisation's currency.** Polar converts, so a multi-currency
business gets one number rather than several. Useful, and worth knowing it
happened.

## Orders, when you need the rows

```js
async function orders(token, from, to) {
  const rows = [];
  let page = 1;

  while (true) {
    const url = new URL("https://api.polar.sh/v1/orders/");
    url.searchParams.set("limit", "100");
    url.searchParams.set("page", String(page));

    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    const body = await res.json();

    for (const order of body.items) {
      const at = new Date(order.created_at).getTime();
      if (at >= from && at < to) rows.push(order);
    }

    if (body.items.length < 100) break;
    page += 1;
  }

  return rows;
}
```

Polar pages with `page` and `limit` rather than a cursor, and
`pagination.max_page` tells you when to stop if you would rather not infer it
from a short page.

Each order carries the customer, the product, the subtotal, the tax and the
net amount. That is what you need for a recent payments feed, and it is what
you need to split revenue by product, which the metrics endpoint will not do.

## Why your totals might not match

Summing order subtotals and asking the metrics endpoint for the same window
should agree, and when they do not it is almost always one of three things.

**Timezone.** The metrics endpoint buckets in whatever timezone you passed.
`created_at` on an order is UTC. Compare them without converting and every
order near midnight is misfiled.

**Refunded orders.** An order refunded later still happened on the day it was
placed. Both figures include it, which is correct and surprises people.

**Pagination.** A loop that stops at the first short page is right. A loop
that stops when `items` is empty makes one wasted call. A loop that trusts a
hardcoded page count is wrong the week you grow.

## In the notch

Notch Metrics reports [Polar revenue](/sources/polar/revenue) from the
metrics endpoint, bucketed hourly, daily, weekly or monthly with a sparkline
and a comparison against the previous window, and
[recent payments](/sources/polar/recent-payments) from the orders list as a
feed of the last ten with who paid.

Both in the MacBook notch, both from one connection whose token never reaches
your Mac. [Everything Polar reports](/sources/polar), or
[download Notch Metrics](/download).
