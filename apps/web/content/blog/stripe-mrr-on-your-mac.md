---
title: "Stripe MRR on your Mac, without opening the dashboard"
description: "Your Stripe MRR, revenue and subscriber count in the MacBook notch. Hover the camera housing to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [stripe, mrr, mac]
faq:
  - question: How do I see my Stripe MRR on my Mac?
    answer: >-
      Install Notch Metrics, connect Stripe on the web, and place the MRR widget
      in the MacBook notch. Hover the camera housing and your MRR is there.
      Notch Metrics runs on Apple silicon, macOS 14 and later.
  - question: Does Notch Metrics store my Stripe secret key on my Mac?
    answer: >-
      No. You paste the key on the web and it is encrypted with a key unique to
      that one connection. The Notch Metrics server calls Stripe and sends your
      Mac a normalised number. The Mac app never holds a Stripe key.
  - question: What Stripe permissions does Notch Metrics need?
    answer: >-
      A restricted key with read access to Charges and Subscriptions. That is
      enough for MRR, revenue, subscribers, churn, refunds and recent payments,
      and a read-only key cannot move money even if it leaked.
  - question: Can I see Stripe and Paddle revenue in the same place?
    answer: >-
      Yes. Notch Metrics connects Stripe, Polar, Paddle, Dodo Payments, Lemon
      Squeezy, RevenueCat and Shopify. Each reports in its own currency and the
      conversion happens on the way out, so a notch showing three providers
      shows one total.
  - question: Is there a free Stripe menu bar app instead?
    answer: >-
      There are several free menu bar apps that show Stripe MRR. Notch Metrics
      is $14 a month or $79 a year, and what you get for it is every connector
      with no per-integration charge, server-side key storage so no credential
      sits on your Mac, and custom metrics for numbers no connector covers.
  - question: How often does the Stripe MRR widget refresh?
    answer: >-
      Each metric is fetched and normalised on a schedule, so the notch holds a
      recent figure rather than calling Stripe every time you look. Hover the
      camera housing and the number is already there.
---

You check Stripe more often than you would admit. Not to do anything, just to
look. Open the tab, wait for the chart, read one number, close the tab.

That loop costs a context switch every time, and the number was never the
expensive part. Getting to it was.

## How do you see Stripe MRR without opening Stripe?

Put it somewhere you already look. Notch Metrics renders your Stripe numbers
in the MacBook notch, the strip of glass around the camera that every other
Mac app pretends is not there. Collapsed, it shows the figures you chose.
Hover, and it expands over whatever you were doing. Move the cursor away and
it folds back.

There is no dock icon and nothing in the menu bar. The app has one surface,
and it exists only while you are looking at it.

## What Stripe numbers you get

Seven, each one a widget you place and size yourself:

| Number                                                     | What it is                                        |
| ---------------------------------------------------------- | ------------------------------------------------- |
| [MRR](/sources/stripe/mrr)                                 | Active subscriptions, each normalised to a month  |
| [Revenue](/sources/stripe/revenue)                         | Gross charges in the window, before fees          |
| [Active subscribers](/sources/stripe/active-subscribers)   | Subscriptions in Stripe status `active` right now |
| [New subscribers](/sources/stripe/new-subscribers)         | Subscriptions created in the window               |
| [Churned subscribers](/sources/stripe/churned-subscribers) | Subscriptions cancelled in the window             |
| [Refunds](/sources/stripe/refunds)                         | Refund balance transactions, as a positive amount |
| [Recent payments](/sources/stripe/recent-payments)         | The last ten succeeded charges, with who paid     |

That last one is the surprise. A feed of the ten most recent payments, with
the payer's billing name, sitting beside the headline figures. You see who
just paid without opening anything.

## Your Stripe key never reaches your Mac

You connect Stripe once, on the web. Paste a key, and it is encrypted with a
key unique to that one connection before it is stored. Our server calls
Stripe and hands your Mac a normalised series of numbers.

That split is deliberate. A desktop app holding a live Stripe secret key is a
laptop you cannot afford to lose, and people lose laptops.

A restricted key with read access to Charges and Subscriptions is enough, and
it is safer than a full secret key: a read-only key cannot move money even if
it leaked. [What the Stripe connector asks for](/sources/stripe).

## Stripe is not the only source

If you take money in more than one place, the notch holds all of it. Revenue
also comes from [Polar](/sources/polar), [Paddle](/sources/paddle),
[Dodo Payments](/sources/dodopayments),
[Lemon Squeezy](/sources/lemonsqueezy) and
[RevenueCat](/sources/revenuecat). Sales come from
[Shopify](/sources/shopify). Each reports in its own currency and the
conversion happens on the way out.

## Getting it

Apple silicon, macOS 14 and later. Seven days of everything, with no card,
then $14 a month or $79 a year with every connector included.

[Download Notch Metrics](/download), connect Stripe, and close the tab.
