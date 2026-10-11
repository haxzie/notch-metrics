---
title: "Polar revenue in your MacBook notch"
description: "MRR, revenue and subscriptions from Polar, in the strip of glass around your Mac's camera. Hover to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [polar, revenue, mac]
faq:
  - question: How do I see Polar MRR on my Mac?
    answer: >-
      Install Notch Metrics, connect Polar on the web with an organisation
      access token, and place the MRR widget in the MacBook notch. Hover the
      camera housing and the figure is there.
  - question: Does Notch Metrics compute its own Polar MRR?
    answer: >-
      No. It reads Polar's own MRR from the metrics endpoint, so the notch and
      the Polar dashboard agree. Polar normalises yearly plans by dividing by
      twelve and excludes trials.
  - question: Does Notch Metrics support Polar sandbox?
    answer: >-
      Yes. The connector asks which mode your token belongs to, sandbox or
      production, because a sandbox token against the production host returns
      401 rather than an empty account.
  - question: Is my Polar access token stored on my Mac?
    answer: >-
      No. The token is encrypted on the server with a key unique to that one
      connection. The Notch Metrics server calls Polar and sends your Mac a
      normalised number.
  - question: Can I show Polar and Stripe revenue together?
    answer: >-
      Yes. Notch Metrics connects Polar, Stripe, Paddle, Dodo Payments, Lemon
      Squeezy, RevenueCat and Shopify, with every connector included on both
      plans and no per-integration charge.
---

Polar's dashboard is good. It is also a browser tab, and a browser tab is
somewhere you have to go.

## How do you watch Polar revenue without a dashboard?

Notch Metrics puts the numbers in the MacBook notch. Collapsed, it is a thin
strip showing what you chose. Hover the camera housing and it expands over
whatever you were doing. Move away and it folds back to the shape it had.

No dock icon, nothing in the menu bar, no tab.

## What Polar reports

| Number                                                      | What it is                           |
| ----------------------------------------------------------- | ------------------------------------ |
| [MRR](/sources/polar/mrr)                                   | Polar's own MRR, trials excluded     |
| [Revenue](/sources/polar/revenue)                           | Order subtotals, before fees and tax |
| [Active subscriptions](/sources/polar/active-subscribers)   | On the latest day Polar has computed |
| [New subscriptions](/sources/polar/new-subscribers)         | Started in the window                |
| [Churned subscriptions](/sources/polar/churned-subscribers) | Ended in the window                  |
| [Recent payments](/sources/polar/recent-payments)           | The last ten orders, newest first    |

Notch Metrics reads MRR and active subscriptions from Polar's own metrics
endpoint rather than recomputing them. Polar normalises yearly plans by
dividing by twelve and excludes trials, and reporting a second opinion would
mean your notch and your Polar dashboard quietly disagreeing.

## One detail worth knowing

Polar computes metrics per period, and the newest period can be empty for a
while as its pipeline catches up. Notch Metrics takes the latest period that
has a value rather than the latest period, so the widget does not read zero
at midnight and then correct itself an hour later.

## Your Polar token stays on the server

Connect Polar once on the web with an organisation access token. It is
encrypted with a key unique to that one connection, and our server calls
Polar and hands your Mac a normalised number. The Mac app never holds the
token. [What the Polar connector asks for](/sources/polar).

Polar runs a sandbox as well as production, and the connector asks which mode
the token belongs to. A sandbox token against the production host returns 401
rather than an empty account, which is at least a clear failure.

## Polar is not the only source

Revenue also comes from [Stripe](/sources/stripe),
[Paddle](/sources/paddle), [Dodo Payments](/sources/dodopayments),
[Lemon Squeezy](/sources/lemonsqueezy) and
[RevenueCat](/sources/revenuecat). Analytics come from
[Plausible](/sources/plausible), [PostHog](/sources/posthog) and others.
[Every source](/sources).

## Getting it

Apple silicon, macOS 14 and later. Seven days with no card, then $14 a month
or $79 a year with every connector included.
[Download Notch Metrics](/download).
