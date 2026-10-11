---
title: "How to get revenue from the Dodo Payments API"
description: "Paging the payments list, which statuses are money, and the live and test host split that makes a good key look like a bad one."
date: 2026-10-11
author: Notch Metrics
tags: [dodopayments, revenue, api]
pillar: dodo-payments-revenue-in-the-notch
faq:
  - question: What is the Dodo Payments API base URL?
    answer: >-
      live.dodopayments.com for live mode and test.dodopayments.com for test
      mode. A key from one used against the other fails to authenticate with a
      message that reads like an invalid key, so check the host before
      regenerating anything.
  - question: Which Dodo Payments statuses count as revenue?
    answer: >-
      Only succeeded. Payments in processing are in flight and failed ones never
      completed. Counting processing payments makes your figure drop when one
      fails, which reads as a refund in a chart and is not one.
  - question: Does Dodo Payments total_amount include tax?
    answer: >-
      Yes. Dodo Payments is a merchant of record, so total_amount is what the
      customer paid including tax that Dodo will remit. It is also gross, before
      refunds and before Dodo's fee.
  - question: How do I separate one-time sales from subscription renewals in Dodo Payments?
    answer: >-
      Filter on whether the payment carries a subscription id. Payments without
      one are one-time purchases. Splitting them matters because recurring
      revenue carries into next month and a one-time sale has to be earned
      again.
  - question: How does pagination work on the Dodo Payments API?
    answer: >-
      With page_number and page_size. Page until you get a page shorter than
      page_size, and bound the loop so an unbounded pager against a large
      account does not run into your rate limit.
---

## Where does Dodo Payments revenue come from?

The payments list. There is no revenue endpoint, so you page
`/payments`, filter to the ones that succeeded, and sum `total_amount`.

```bash
curl -s 'https://live.dodopayments.com/payments?created_at_gte=2026-10-01T00:00:00Z&created_at_lte=2026-10-08T00:00:00Z&page_size=100' \
  -H 'Authorization: Bearer <api key>'
```

## Two hosts, and the error that looks like something else

Dodo Payments splits test and live by hostname.

- Live: `live.dodopayments.com`
- Test: `test.dodopayments.com`

A live key against the test host fails to authenticate, and the message says
your key is invalid. It is not. It is in the wrong place. This costs people
an hour because the obvious reading of an auth error is a bad key, and the
first thing everybody does is regenerate one.

Check the host before you rotate anything.

## Which payments are money

Filter on `status` being `succeeded`. Dodo Payments also reports `processing`
and `failed`, and a payment in flight is not revenue. Counting it means your
figure drops when something fails, which reads as a refund in your chart and
is not one.

```js
const succeeded = payments.filter((p) => p.status === "succeeded");
const total = succeeded.reduce((sum, p) => sum + p.total_amount, 0);
```

## total_amount includes tax

`total_amount` is what the customer paid, in minor units, including tax. Dodo
Payments is a merchant of record, so it collected that tax and it will remit
it. The portion is not yours.

That makes a Dodo Payments revenue figure higher than an equivalent Stripe
one, which does not include tax. Comparing them directly overstates the
Dodo side, and the gap is roughly your VAT rate.

It is also gross: before refunds and before Dodo's fee.

## Subscription renewals and one-time purchases are mixed

The payments list contains both. A renewal and a one-off purchase look
similar, and what separates them is whether the payment carries a
subscription id.

```js
const oneTime = succeeded.filter((p) => !p.subscription_id);
```

Splitting them is worth doing. Recurring revenue carries into next month. A
one-time sale has to be earned again. A total that holds steady while the
recurring half shrinks is a business quietly changing shape.

## Pagination

Dodo Payments pages with `page_number` and `page_size`. Page until you get a
page shorter than `page_size`.

```js
async function payments(key, host, from, to) {
  const rows = [];
  let page = 0;

  while (true) {
    const url = new URL(`https://${host}/payments`);
    url.searchParams.set("created_at_gte", from);
    url.searchParams.set("created_at_lte", to);
    url.searchParams.set("page_size", "100");
    url.searchParams.set("page_number", String(page));

    const res = await fetch(url, { headers: { Authorization: `Bearer ${key}` } });
    const body = await res.json();
    const items = body.items ?? [];

    rows.push(...items);
    if (items.length < 100) break;
    page += 1;
  }

  return rows;
}
```

Bound the loop. An unbounded pager against a large account will page until
something gives up, and that something is usually your rate limit.

## Or read it in the notch

Notch Metrics reports
[Dodo Payments total revenue](/sources/dodopayments/revenue) and
[one-time sales](/sources/dodopayments/one-time-sales) as separate widgets in
the MacBook notch, both gross and before fees, both bucketed hourly, daily,
weekly or monthly with a sparkline.

Connect once on the web, pick live or test, and the key never reaches your
Mac. [Everything Dodo Payments reports](/sources/dodopayments), or
[download Notch Metrics](/download).
