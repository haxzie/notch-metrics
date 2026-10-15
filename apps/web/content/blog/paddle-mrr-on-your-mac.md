---
title: "Paddle MRR on your Mac"
description: "Paddle MRR, revenue and subscriptions in the MacBook notch. Hover the camera housing to look, move away and the notch is untouched."
date: 2026-10-11
author: Notch Metrics
tags: [paddle, mrr, mac]
faq:
  - question: How do I see Paddle MRR on my Mac?
    answer: >-
      Install Notch Metrics, connect Paddle on the web with an API key, and
      place the MRR widget in the MacBook notch. Hover the camera housing and
      the figure is there.
  - question: Does Paddle revenue include tax?
    answer: >-
      Yes. Paddle is a merchant of record and collects tax on your behalf, so
      its transaction totals include it. A Paddle revenue figure is therefore
      higher than an equivalent Stripe one, which does not include tax.
  - question: Does Notch Metrics support Paddle sandbox?
    answer: >-
      Yes. The connector asks which mode your API key belongs to, because Paddle
      runs its sandbox on a different host and a sandbox key against production
      returns 401.
  - question: Why are Paddle subscription counts slower than revenue?
    answer: >-
      Paddle's API cannot filter subscriptions by date. Counting subscriptions
      that started or ended in a window means reading the whole subscription
      list and filtering it client-side.
  - question: Is my Paddle API key stored on my Mac?
    answer: >-
      No. It is encrypted on the server with a key unique to that one
      connection. The Notch Metrics server calls Paddle and sends your Mac a
      normalised number.
---

Paddle is a merchant of record, which means it handles tax, invoicing and
compliance for you. It also means one more dashboard to open.

## How do you see Paddle MRR without the dashboard?

Put it in the notch. Notch Metrics renders your Paddle figures in the strip
of glass around your Mac's camera. Collapsed, a thin line of numbers. Hover,
and it expands over whatever you were doing. Move away and it folds back.

## What Paddle reports

| Number                                                       | What it is                                       |
| ------------------------------------------------------------ | ------------------------------------------------ |
| [MRR](/sources/paddle/mrr)                                   | Active subscriptions, normalised to a month      |
| [Revenue](/sources/paddle/revenue)                           | Transactions billed in the window, including tax |
| [Active subscriptions](/sources/paddle/active-subscribers)   | Status `active` right now                        |
| [New subscriptions](/sources/paddle/new-subscribers)         | Started in the window                            |
| [Churned subscriptions](/sources/paddle/churned-subscribers) | Cancelled in the window                          |
| [Recent payments](/sources/paddle/recent-payments)           | The last ten transactions                        |

Paddle revenue includes tax, because as merchant of record Paddle collected
it. That is worth remembering when comparing against a Stripe figure, which
does not.

## The Paddle quirk that shapes everything

Paddle's API cannot filter subscriptions by date. There is no
`started_at[gte]`. To count subscriptions that began last week, you read the
whole subscription list and filter it yourself.

Notch Metrics does exactly that, bounded so it cannot run away on a large
account. It is worth knowing because it explains why new and churned
subscription figures are the slow ones, and why anybody building this
themselves hits a wall at scale.

## Sandbox and production

Paddle runs a sandbox on a different host. The connector asks which mode your
key belongs to, because a sandbox key against the production host returns 401
rather than an empty account.
[What the Paddle connector asks for](/sources/paddle).

Your API key is encrypted on the server with a key unique to that one
connection. The Mac app never holds it.

## Not just Paddle

Revenue also comes from [Stripe](/sources/stripe),
[Polar](/sources/polar), [Dodo Payments](/sources/dodopayments),
[Lemon Squeezy](/sources/lemonsqueezy) and
[RevenueCat](/sources/revenuecat). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
