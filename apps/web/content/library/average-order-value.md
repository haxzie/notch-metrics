---
title: "What is average order value?"
description: "AOV is sales divided by orders, and almost every chart of it is computed wrongly. Why the headline is not the average of the points."
date: 2026-10-11
author: Notch Metrics
tags: [aov, glossary, ecommerce]
kind: glossary
term: Average order value
faq:
  - question: How do you calculate average order value?
    answer: >-
      Total sales divided by the total number of orders over the same period. Do
      not average the daily ratios: that weights a quiet Sunday equally with
      Black Friday, and a single expensive order can move it by a third.
  - question: Why does my AOV headline not match my AOV chart?
    answer: >-
      Because each chart point is that day's own ratio and the headline is the
      period's total sales divided by its total orders. They are not supposed to
      match, and a tool whose headline equals the mean of its points is
      calculating it wrongly.
  - question: Should refunded orders count in AOV?
    answer: >-
      Either, as long as both sides match. Include them in sales and in the
      order count and AOV is the average value of orders placed. Exclude from
      both and it is the average value of orders kept. Filtering one and not the
      other is the common bug.
  - question: Is average order value the same as average revenue per customer?
    answer: >-
      No. AOV divides by orders; revenue per customer divides by customers. A
      customer who orders four times contributes four orders and one customer,
      so the two diverge as repeat purchasing rises.
  - question: What should I use instead of AOV if one order can move it?
    answer: >-
      The median order value. If a single wholesale order visibly moves your
      mean, the mean is the wrong statistic for that business.
---

**Average order value is total sales divided by the number of orders over the
same period.** Two numbers, one division, and a surprising amount of ways to
get it wrong.

## The calculation most tools get wrong

There are two ways to compute AOV over a week and only one of them is right.

**Weighted.** Sum the week's sales, sum the week's orders, divide.

**Unweighted.** Compute each day's AOV, then average the seven values.

The second treats a Sunday with two orders as equal in weight to a Black
Friday with two thousand. One quiet day with a single expensive order can
move it by a third.

```
Right:  total_sales / total_orders
Wrong:  mean(daily_sales / daily_orders)
```

This is also why a correctly drawn AOV chart looks inconsistent: each point
is that day's own ratio, and the headline is the period's ratio. They are not
supposed to match. A tool whose headline equals the mean of its points is
doing the wrong calculation.

## Use the same filter on both sides

The easiest bug to write here. Filter the sales sum to exclude refunded
orders, forget to filter the order count, and AOV quietly drops.

Whichever rule you pick, apply it to numerator and denominator:

- **Include refunded orders in both.** AOV is the average value of orders
  placed.
- **Exclude from both.** AOV is the average value of orders kept.

Both are defensible. Only mixing them is not.

## What moves AOV, and what to do about each

**Price increases** move it evenly across every order. Expected, and the
easiest to read.

**Bundles and upsells** move it only for the orders that take them, so the
mean rises while the median order does not change at all. If AOV is up and
nothing feels different, check the distribution before celebrating.

**One wholesale order** moves it for a single day and then it falls back. If
a single order can visibly move your AOV, the mean is the wrong statistic and
you want the median.

## AOV is a ratio, so read it with volume

AOV rising while orders fall is a smaller, richer customer base. That might
be the strategy or it might be a problem, and the ratio alone cannot say
which.

Always place sales and orders beside it. Three numbers explain each other;
one explains nothing.

## AOV in Notch Metrics

[Shopify average order value](/sources/shopify/average-order-value) is
reported as sales divided by orders over the whole window, with each
sparkline point being that day's own ratio. The page says so, because the
apparent inconsistency is a correct calculation and not a bug.

Place it beside [sales](/sources/shopify/revenue) and
[orders](/sources/shopify/orders).

[How to calculate AOV from Shopify orders](/blog/calculate-average-order-value-from-shopify-orders)
