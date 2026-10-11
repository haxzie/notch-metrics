---
title: "How to calculate average order value from Shopify orders"
description: "AOV is sales divided by orders, and almost every chart of it is wrong. Why the headline is not the average of the points, and what moves it."
date: 2026-10-11
author: Notch Metrics
tags: [shopify, aov, api]
pillar: shopify-sales-and-orders-in-your-notch
faq:
  - question: How do you calculate average order value?
    answer: >-
      Sum sales over the window and divide by the number of orders in the same
      window. Do not average the daily ratios: that weights a quiet Sunday
      equally with Black Friday and a single expensive order can move it by a
      third.
  - question: Why does my AOV headline not match the average of the chart?
    answer: >-
      Because each chart point is that day's own ratio and the headline is the
      window's total sales divided by its total orders. They are not supposed to
      match, and a tool whose headline equals the mean of its points is doing
      the wrong calculation.
  - question: Should refunded orders count in average order value?
    answer: >-
      Either, as long as you are consistent. Include them in both numerator and
      denominator and AOV is the average value of orders placed. Exclude from
      both and it is the average value of orders kept. Excluding from one and
      not the other is the common bug.
  - question: What moves average order value?
    answer: >-
      Price changes move it evenly. Bundles and upsells move it only for the
      orders that take them, so AOV rises while the median order does not. A
      single wholesale order moves it for a day and then it falls back.
  - question: Can I compute AOV across multiple currencies?
    answer: >-
      Only after converting. Sum shopMoney, which is the store's own currency
      and already normalised. Averaging presentmentMoney across mixed currencies
      produces a number with no units.
---

## What is average order value?

Total sales divided by the number of orders over the same window. Two fields,
one division. The arithmetic is trivial and the reporting is where it goes
wrong.

## The mistake nearly everyone makes

There are two ways to compute AOV over a week and they give different
answers.

**Weighted.** Sum the week's sales, sum the week's orders, divide.

**Unweighted.** Compute each day's AOV, then average the seven numbers.

The first is correct. The second treats a Sunday with two orders as equal in
weight to a Black Friday with two thousand, and a single quiet day with one
expensive order can move it by a third.

```js
// Right.
const aov = totalSales / totalOrders;

// Wrong, and it will look plausible for months.
const aov = days.reduce((sum, d) => sum + d.sales / d.orders, 0) / days.length;
```

This is also why a correct AOV chart looks inconsistent: each point is that
day's own ratio, and the headline is the window's ratio. They are not
supposed to match, and a tool whose headline equals the mean of its points is
doing the wrong calculation.

## Getting the two numbers

One GraphQL query gives you both, because the order count is the number of
nodes you summed.

```graphql
query Orders($query: String!, $cursor: String) {
  orders(first: 250, query: $query, after: $cursor) {
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

Count the nodes you include in the sales total, and divide at the end. Count
and sum have to use the same filter, or the ratio is meaningless.

## Decide about cancelled and refunded orders once

An order that was placed and then refunded happened. It had a value. Include
it in both numerator and denominator and your AOV is the average value of
orders placed.

Exclude it from both and your AOV is the average value of orders kept. Also
defensible.

What is not defensible is excluding it from one and not the other, which is
the easiest bug to write here: filter the sales sum on financial status and
forget to filter the count, and the AOV quietly drops.

## Currency

`shopMoney` is in the store's currency. A store selling in several
presentment currencies still has one shop currency, so this is already
normalised and the division is safe.

If you are summing `presentmentMoney` for some reason, AOV across mixed
currencies is a number with no units.

## What actually moves AOV

Three things, and they call for different responses.

**Price changes** move it evenly across every order.

**Bundles and upsells** move it only for the orders that take them, so AOV
rises while the median order stays put. Worth watching the distribution, not
just the mean.

**One wholesale order** moves it for a day and then it falls back. If a
single order can move your AOV visibly, the mean is the wrong statistic and
you want the median.

## In the notch

Notch Metrics reports
[Shopify average order value](/sources/shopify/average-order-value) as sales
divided by orders over the whole window, with each sparkline point being that
day's own ratio. The page says so, so the apparent inconsistency is
documented rather than discovered.

Place it beside [sales](/sources/shopify/revenue) and
[orders](/sources/shopify/orders) and the three explain each other.
[Everything Shopify reports](/sources/shopify), or
[download Notch Metrics](/download).
