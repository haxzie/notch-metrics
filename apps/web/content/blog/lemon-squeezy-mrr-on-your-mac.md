---
title: "Lemon Squeezy MRR on your Mac"
description: "MRR, revenue, subscriptions and refunds from Lemon Squeezy, in the MacBook notch. Hover to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [lemonsqueezy, mrr, mac]
faq:
  - question: How do I see Lemon Squeezy MRR on my Mac?
    answer: >-
      Install Notch Metrics, connect Lemon Squeezy on the web with an API key
      and a store id, and place the MRR widget in the MacBook notch. Hover the
      camera housing and the figure is there.
  - question: Does the Lemon Squeezy active subscriber count include trials?
    answer: >-
      Yes. Lemon Squeezy counts a trialling subscription as active, and Notch
      Metrics reports what Lemon Squeezy reports rather than second-guessing it.
      The figure is the paying book plus the people still deciding.
  - question: Why are Lemon Squeezy refunds bucketed by order date?
    answer: >-
      Because the API exposes refunded_amount on the order but not the date the
      refund happened. A refund this week on an order from March therefore
      appears in March.
  - question: Can Notch Metrics handle more than one Lemon Squeezy store?
    answer: >-
      Yes, as separate connections. A Lemon Squeezy account can hold several
      stores and the connector asks which one, so add a second connection for a
      second store.
  - question: Is my Lemon Squeezy API key stored on my Mac?
    answer: >-
      No. It is encrypted on the server with a key unique to that one
      connection. The Notch Metrics server calls Lemon Squeezy and sends your
      Mac a normalised number.
---

Lemon Squeezy handles the tax and the invoicing. It does not handle the habit
of opening the dashboard twelve times a day to read one number.

## How do you see Lemon Squeezy MRR without the dashboard?

Notch Metrics puts it in the MacBook notch, the strip of glass around the
camera. Collapsed, a thin line of figures. Hover and it expands over whatever
you were doing. Move away and it folds back.

No dock icon, nothing in the menu bar.

## What Lemon Squeezy reports

| Number                                                         | What it is                                  |
| -------------------------------------------------------------- | ------------------------------------------- |
| [MRR](/sources/lemonsqueezy/mrr)                               | Active subscriptions, normalised to a month |
| [Revenue](/sources/lemonsqueezy/revenue)                       | Orders in the window that took payment      |
| [Active subscribers](/sources/lemonsqueezy/active-subscribers) | Status `active`, trials included            |
| [Refunds](/sources/lemonsqueezy/refunds)                       | Refunded amounts on orders in the window    |
| [Recent payments](/sources/lemonsqueezy/recent-payments)       | The last ten orders                         |

Two of those carry caveats worth knowing before you trust them.

**Active subscribers includes trials.** Lemon Squeezy counts a trialling
subscription as active, and Notch Metrics reports what Lemon Squeezy reports
rather than second-guessing it. So the figure is the book plus the people
still deciding.

**Refunds are bucketed by the order date.** Lemon Squeezy exposes
`refunded_amount` on the order but not the date the refund happened, so a
refund lands on the day the original order was placed. A refund this week on
an order from March appears in March. [Why that matters](/sources/lemonsqueezy/refunds).

Both of those are stated on the pages rather than buried, because a number
whose definition is hidden is a number you cannot argue with.

## One store, or several

Lemon Squeezy accounts can hold more than one store, and the connector asks
which one. Add a second connection for a second store.
[What the Lemon Squeezy connector asks for](/sources/lemonsqueezy).

Your API key is encrypted on the server with a key unique to that one
connection. The Mac app never holds it, so the number in your notch cost you
no credential on the device.

## Alongside everything else

Revenue also comes from [Stripe](/sources/stripe), [Polar](/sources/polar),
[Paddle](/sources/paddle), [Dodo Payments](/sources/dodopayments) and
[RevenueCat](/sources/revenuecat). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
