---
title: "Shopify sales and orders in your MacBook notch"
description: "Sales, orders, average order value and customers from Shopify, in the strip of glass around your Mac's camera. No tab to open."
date: 2026-10-11
author: Notch Metrics
tags: [shopify, sales, mac]
faq:
  - question: How do I see Shopify sales on my Mac without opening the admin?
    answer: >-
      Install Notch Metrics, connect Shopify on the web with your shop domain
      and a custom app access token, and place the sales widget in the MacBook
      notch. Hover the camera housing and the figure is there.
  - question: What Shopify permissions does Notch Metrics need?
    answer: >-
      Read access to orders and customers. That is the smallest set that answers
      sales, orders, average order value, refunds and customer counts, and a
      read-only token cannot change anything in the store.
  - question: Does Notch Metrics show Shopify average order value?
    answer: >-
      Yes, as its own widget. It is sales divided by orders over the window, and
      each sparkline point is that day's own ratio, so the headline is
      deliberately not the average of the points.
  - question: Is my Shopify access token stored on my Mac?
    answer: >-
      No. It is encrypted on the server with a key unique to that one
      connection. The Notch Metrics server calls Shopify and sends your Mac a
      normalised number.
  - question: Can I show Shopify and Stripe in the same notch?
    answer: >-
      Yes. Notch Metrics connects Shopify alongside Stripe, Polar, Paddle, Dodo
      Payments, Lemon Squeezy and RevenueCat, with every connector included and
      no per-integration charge.
---

Shopify's admin is a good dashboard and a slow page. On a busy day you open
it to read one number and wait for twelve.

## How do you watch Shopify sales without the admin?

Notch Metrics puts the figures in the MacBook notch. Collapsed, a thin strip.
Hover the camera housing and it expands over whatever you were doing. Move
away and it folds back to the shape it had.

## What Shopify reports

| Number                                                      | What it is                                |
| ----------------------------------------------------------- | ----------------------------------------- |
| [Sales](/sources/shopify/revenue)                           | Order totals for orders that took payment |
| [Orders](/sources/shopify/orders)                           | Orders placed in the window               |
| [Average order value](/sources/shopify/average-order-value) | Sales divided by orders                   |
| [Refunds](/sources/shopify/refunds)                         | Refunded amounts in the window            |
| [New customers](/sources/shopify/new-customers)             | First-time buyers                         |
| [Customers](/sources/shopify/customers)                     | Every customer record, ever               |
| [Recent payments](/sources/shopify/recent-payments)         | The last ten orders                       |

The first three belong together. Sales rising on flat orders is a bigger
basket. Sales rising on flat average order value is simply more customers.
One widget cannot tell you which; three can.

## Connecting

A shop domain and a custom app access token.
[What the Shopify connector asks for](/sources/shopify). The token needs read
access to orders and customers and nothing else, which is the smallest set
that answers these questions.

It is encrypted on the server with a key unique to that one connection, bound
to your account and the provider, so the Mac app never holds it.

## The connector is in beta

Shopify's connector is marked beta on [its page](/sources/shopify), and
beta here means the edges are still being worked on rather than that the
numbers are unavailable. It connects and it returns figures today.

## Alongside everything else

If you also take subscription revenue, [Stripe](/sources/stripe),
[Polar](/sources/polar), [Paddle](/sources/paddle),
[Dodo Payments](/sources/dodopayments) and
[Lemon Squeezy](/sources/lemonsqueezy) sit in the same notch. Traffic comes
from [Plausible](/sources/plausible) and
[Google Analytics](/sources/google-analytics), search from
[Search Console](/sources/google-search-console). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year with every connector included.
[Download Notch Metrics](/download).
