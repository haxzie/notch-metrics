---
title: "How to count new against returning Shopify customers"
description: "First-time buyers, lifetime totals and guest checkout. Why the obvious Shopify customer count inflates, and what to use instead."
date: 2026-10-11
author: Notch Metrics
tags: [shopify, customers, api]
pillar: shopify-sales-and-orders-in-your-notch
faq:
  - question: Does Shopify create a customer record for guest checkout?
    answer: >-
      Yes. Shopify creates a customer from the email on the order whether or not
      an account exists, so the customer list is a list of buyers and newsletter
      signups rather than registered users.
  - question: How do I count first-time buyers in Shopify?
    answer: >-
      Query customers created in the window and filter to those whose
      numberOfOrders is greater than zero. A record with zero orders is a
      newsletter signup, not a buyer.
  - question: How do I count returning Shopify customers?
    answer: >-
      Subtract. Page orders in the window and collect distinct customer ids,
      then subtract the customers whose first order fell in that window. Shopify
      does not report returning customers directly, and paging customers tells
      you who was created rather than who bought.
  - question: Why does my Shopify repeat purchase rate look poor?
    answer: >-
      Often guest checkout. A shopper using a different email each time is a new
      customer each time, because Shopify matches on email and on account. There
      is no API field that fixes it, so read the direction rather than the
      absolute value.
  - question: Can the Shopify total customer count go down?
    answer: >-
      Yes. A record removed for a GDPR erasure request is deleted rather than
      flagged, so the lifetime total falls. It is otherwise a number that only
      goes up.
---

## What makes a Shopify customer new?

Their first order falls inside your window. That is it, and the complication
is entirely in how Shopify records customers in the first place.

## Shopify creates a customer at checkout

You do not need an account for Shopify to record you. Place an order as a
guest and Shopify creates a customer record from the email on the order.

That is convenient and it means the customer list is not a list of registered
users. It contains buyers, and it also contains anybody who signed up for the
newsletter, which is the part that quietly inflates every count built on it.

## Two different numbers

**New customers** counts customer records created in the window. It is the
flow.

**Customers** counts every record the store has ever held. It is a lifetime
total, it only goes up, and a window selector does nothing to it.

Those answer different questions and reporting either as "customers" without
saying which is how two people in the same company end up arguing about a
number they both read correctly.

## The query

```graphql
query Customers($query: String!, $cursor: String) {
  customers(first: 250, query: $query, after: $cursor) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      createdAt
      numberOfOrders
      amountSpent {
        amount
        currencyCode
      }
    }
  }
}
```

With a search query of
`created_at:>='2026-10-01T00:00:00Z' created_at:<'2026-10-08T00:00:00Z'`.

`numberOfOrders` is the useful field here. A record with zero orders is a
newsletter signup, not a buyer, and filtering them out gives you first-time
buyers rather than first-time records.

```js
const firstTimeBuyers = nodes.filter((c) => Number(c.numberOfOrders) > 0);
```

## Returning customers are a subtraction

Shopify does not report returning customers directly. Over a window:

```
returning = distinct customers who ordered  minus  customers whose first order was in the window
```

The first half means paging orders and collecting distinct customer ids, not
paging customers. An order carries its customer, and that is the only way to
know who bought in a window rather than who was created in it.

## Guest checkout inflates everything

A shopper who checks out with a different email each time is a new customer
each time. Shopify matches on email, and on the account where one exists.

On a store with no account requirement this is a meaningful distortion, and
there is no API field that fixes it. Read the direction of the number rather
than the absolute value, and be suspicious of a repeat-purchase rate that
looks unusually poor.

## Deletions

A customer record removed for a GDPR erasure request is gone, not flagged. So
the lifetime total can fall, despite being a number that otherwise only goes
up. Worth knowing before you treat a dip as a data problem.

## In the notch

Notch Metrics reports
[Shopify new customers](/sources/shopify/new-customers) as customer records
created in the window, and [customers](/sources/shopify/customers) as the
lifetime total, which is a snapshot with no sparkline because a window does
not apply to it.

Both pages say plainly what they include, newsletter signups and all, because
a count whose definition is hidden is a count you cannot act on.
[Everything Shopify reports](/sources/shopify), or
[download Notch Metrics](/download).
