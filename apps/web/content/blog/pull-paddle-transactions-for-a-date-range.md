---
title: "How to pull Paddle transactions for a date range"
description: "Billed date against created date, what the total actually includes, and why Paddle revenue is higher than the equivalent Stripe figure."
date: 2026-10-11
author: Notch Metrics
tags: [paddle, revenue, api]
pillar: paddle-mrr-on-your-mac
faq:
  - question: How do I filter Paddle transactions by date?
    answer: >-
      Use the square-bracket operator syntax, such as billed_at[GTE] and
      billed_at[LT], with RFC 3339 timestamps. The operators are case-sensitive:
      [GTE] works and [gte] does not.
  - question: Should I bucket Paddle revenue by created_at or billed_at?
    answer: >-
      billed_at. A renewal is often created before it is billed, and a
      transaction that sat in past_due while dunning ran was created one week
      and billed the next. Bucketing by creation puts the money on the wrong
      day.
  - question: What is the difference between total and earnings on a Paddle transaction?
    answer: >-
      total is what the customer paid, including tax. earnings is what you will
      be paid out, after Paddle's fee and after tax. Paddle is a merchant of
      record, so the tax portion is not yours.
  - question: Why is Paddle revenue higher than the same figure in Stripe?
    answer: >-
      Because Paddle totals include tax and Stripe gross charges do not. Paddle
      is a merchant of record and collects VAT on your behalf, so the two are
      not a like-for-like comparison.
  - question: How does pagination work on the Paddle API?
    answer: >-
      Paddle returns a cursor at meta.pagination.next, which already carries
      your filters. Page until there is no next link rather than until you see a
      short page, because Paddle can return a short page with more to come.
---

## How do you get Paddle revenue for a window?

List transactions, filter by billing date, and sum the totals.

```bash
curl -s 'https://api.paddle.com/transactions?billed_at[GTE]=2026-10-01T00:00:00Z&billed_at[LT]=2026-10-08T00:00:00Z&status=completed&per_page=100' \
  -H 'Authorization: Bearer pdl_live_...'
```

The square-bracket operator syntax is Paddle's, and it is case-sensitive:
`[GTE]` works, `[gte]` does not. Dates are RFC 3339.

## Billed, created, or updated

A Paddle transaction carries several timestamps and picking the wrong one
produces a figure that is plausible and wrong.

| Field        | What it means                            |
| ------------ | ---------------------------------------- |
| `created_at` | When the transaction record was made     |
| `billed_at`  | When it was actually billed              |
| `updated_at` | Any change, including status transitions |

Use `billed_at`. A subscription renewal is often created before it is
billed, and a transaction that sat in `past_due` for a week while dunning ran
was created last Monday and billed this Monday. Bucketing by creation puts
the money on the wrong day.

## Which statuses are money

`completed` and `paid` are revenue. `draft` and `ready` have not been
charged. `billed` is awaiting payment. `canceled` and `past_due` are not
money you have.

Filtering on `status=completed` alone misses accounts that settle into
`paid`, so take both unless you have checked which yours produces.

## The total includes tax

`details.totals.total` is the amount charged including tax, in minor units,
as a string. Paddle is a merchant of record: it collected the VAT and it will
remit it, and that portion is not yours.

If you want your own take, `details.totals.earnings` is after Paddle's fee
and after tax. The two answer different questions:

- `total` is what the customer paid.
- `earnings` is what you will be paid out.

Pick one and label your chart accordingly. A Paddle `total` compared against
a Stripe gross figure is not a like-for-like comparison, because Stripe's
does not include tax.

## Currency

Each transaction has its own `currency_code`, and Paddle sells in many.
Summing totals across currencies without converting produces a number with no
meaning. Either filter to one currency or convert, and if you convert, record
the rate and the date you used.

## Pagination

```js
async function transactions(key, from, to) {
  const rows = [];
  let url = `https://api.paddle.com/transactions?billed_at[GTE]=${from}&billed_at[LT]=${to}&per_page=100`;

  while (url) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${key}` } });
    const body = await res.json();
    rows.push(...body.data);
    // Page until there is no next link. A short page does not mean the end.
    url = body.meta?.pagination?.next ?? null;
  }

  return rows;
}
```

The `next` link already carries your filters, so do not rebuild it.

## Or put it in the notch

Notch Metrics reports [Paddle revenue](/sources/paddle/revenue) from
transactions billed in the window that are paid or completed, by their total
including tax, before Paddle's fee, bucketed by billing date. Hourly, daily,
weekly or monthly, with a sparkline and a comparison against the previous
window.

It also reports [recent payments](/sources/paddle/recent-payments) as a feed
of the last ten transactions with who paid.
[Everything Paddle reports](/sources/paddle), or
[download Notch Metrics](/download).
