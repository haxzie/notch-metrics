---
title: "How to get daily sales totals from the Shopify Admin API"
description: "There is no sales endpoint. How to query orders with GraphQL, which money field to sum, and the pagination that bites at scale."
date: 2026-10-11
author: Notch Metrics
tags: [shopify, sales, api]
pillar: shopify-sales-and-orders-in-your-notch
faq:
  - question: Which Shopify API should I use for sales totals?
    answer: >-
      The GraphQL Admin API. The REST order endpoints are legacy and capped, and
      GraphQL returns exactly the fields you ask for instead of a full order
      object per row.
  - question: What is the difference between totalPriceSet and currentTotalPriceSet in Shopify?
    answer: >-
      totalPriceSet is the order total when it was placed. currentTotalPriceSet
      is the total now, after any edits and refunds. For a sales figure that
      reconciles, currentTotalPriceSet is usually the right one.
  - question: What is shopMoney against presentmentMoney in Shopify?
    answer: >-
      shopMoney is the amount in the store's own currency and presentmentMoney
      is what the customer actually paid in. Sum shopMoney, or you are adding
      yen to euros.
  - question: Why is my Shopify sales total far too high?
    answer: >-
      Often a malformed term in the query search string. Shopify's search syntax
      tends to ignore a bad term rather than reject it, so a typo in a
      created_at filter returns every order in the store instead of an error.
  - question: How does rate limiting work on the Shopify GraphQL API?
    answer: >-
      By query cost, not request count. The response carries extensions.cost
      with your remaining points and restore rate. A 250-node order query is
      expensive, so read the throttle status and back off on it rather than
      retrying blindly.
---

## Does Shopify have a sales endpoint?

No. The admin shows a sales figure; the API does not return one. You query
orders and sum them, and the two decisions that matter are which API and
which money field.

## Use GraphQL, not REST

Shopify's REST Admin API is legacy and the order endpoints there are capped
and deprecated. The GraphQL Admin API is where new work belongs, and for this
job it is also genuinely better: one query returns exactly the fields you
want instead of a full order object per row.

```graphql
query Orders($query: String!, $cursor: String) {
  orders(first: 250, query: $query, after: $cursor, sortKey: CREATED_AT) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      createdAt
      displayFinancialStatus
      currentTotalPriceSet {
        shopMoney {
          amount
          currencyCode
        }
      }
    }
  }
}
```

POST it to
`https://{shop}.myshopify.com/admin/api/{version}/graphql.json` with an
`X-Shopify-Access-Token` header.

## The query string is a search syntax

`query` is not GraphQL, it is Shopify's own search language, passed as a
string.

```
created_at:>='2026-10-01T00:00:00Z' created_at:<'2026-10-08T00:00:00Z'
```

Terms are space-separated and implicitly ANDed. Quote the timestamps. A
malformed term is usually ignored rather than rejected, which means a typo
returns every order in the store instead of an error, and the first sign of
trouble is a sales figure that is far too high.

## Which money field

Shopify has several and they answer different questions.

| Field                  | What it is                             |
| ---------------------- | -------------------------------------- |
| `totalPriceSet`        | The order total when it was placed     |
| `currentTotalPriceSet` | The total now, after edits and refunds |
| `subtotalPriceSet`     | Before tax and shipping                |
| `totalReceivedSet`     | What was actually captured             |

`currentTotalPriceSet` is usually what you want for a sales figure, because
an order edited after the fact should report its real value. If you want the
original, use `totalPriceSet` and be aware that your total will not reconcile
against anything.

Every one of them is a `MoneySet` with two members: `shopMoney` in the
store's currency and `presentmentMoney` in whatever the customer paid in.
Sum `shopMoney` or you are adding yen to euros.

## Amounts are decimal strings

`amount` comes back as `"129.95"`, a string. Convert to minor units as an
integer before you do anything with it, and never hold money in a float.

```js
const minor = Math.round(Number(amount) * 100);
```

That rounding step is not optional. `Number("129.95") * 100` is
`12994.999999999998`.

## Financial status

`displayFinancialStatus` tells you whether money moved: `PAID`,
`PARTIALLY_PAID`, `PENDING`, `REFUNDED`, `VOIDED`, `AUTHORIZED`.

Include `PAID`, `PARTIALLY_PAID` and `REFUNDED` in a gross figure. A refunded
order still took money on the day it was placed, and refunds belong in their
own number. Exclude `PENDING`, `VOIDED` and `AUTHORIZED`, which have not
been captured.

## Pagination and the cost limit

GraphQL pages with `first` and `after`, up to 250 nodes. Follow
`pageInfo.endCursor` until `hasNextPage` is false.

Shopify also meters by query cost rather than by request count. The response
carries `extensions.cost` with your remaining points and the restore rate,
and a 250-node order query is expensive. Read the throttle status and back
off on it rather than retrying blindly, or a busy store will lock you out
mid-sum.

## In the notch

Notch Metrics reports [Shopify sales](/sources/shopify/revenue) as order
totals for orders placed in the window that took payment, in the store's own
currency, gross: a later refund does not remove the order from the day it was
placed, and [refunds](/sources/shopify/refunds) are the other half.

Hourly, daily, weekly or monthly, with a sparkline and a comparison against
the previous window. [Everything Shopify reports](/sources/shopify), or
[download Notch Metrics](/download).
