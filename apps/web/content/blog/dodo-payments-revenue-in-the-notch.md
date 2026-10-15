---
title: "Dodo Payments revenue in the notch"
description: "Revenue, MRR and orders from Dodo Payments in the MacBook notch. Hover the camera housing to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [dodopayments, revenue, mac]
faq:
  - question: How do I see Dodo Payments revenue on my Mac?
    answer: >-
      Install Notch Metrics, connect Dodo Payments on the web with an API key,
      and place the revenue widget in the MacBook notch. Hover the camera
      housing and the figure is there.
  - question: Does Notch Metrics separate Dodo Payments subscriptions from one-time sales?
    answer: >-
      Yes, as two widgets. Total revenue counts every succeeded payment, and
      one-time sales counts only payments not tied to a subscription. Placing
      both shows whether a steady total is hiding movement underneath.
  - question: Does Notch Metrics support Dodo Payments test mode?
    answer: >-
      Yes. The connector asks which mode your API key belongs to, because Dodo
      Payments runs test and live on separate hosts and a test key against the
      live host fails to authenticate.
  - question: Is my Dodo Payments API key stored on my Mac?
    answer: >-
      No. It is encrypted on the server with a key unique to that one
      connection, bound to your account and the provider. The Notch Metrics
      server calls Dodo Payments and sends your Mac a normalised number.
  - question: What does Dodo Payments MRR count?
    answer: >-
      Active subscriptions, each recurring pre-tax amount normalised to a
      monthly amount using its payment frequency. It is a snapshot of the book
      right now rather than a total over the window.
---

Dodo Payments is a merchant of record for software, which means it takes the
tax and compliance problem off your desk. The numbers still live in a
dashboard, and the dashboard is still a tab.

## How do you watch Dodo Payments revenue without a tab?

Notch Metrics puts it in the MacBook notch. Collapsed, a thin strip of
figures. Hover the camera housing and it expands over whatever you were
doing. Move the cursor away and it folds back to the shape it had.

## What Dodo Payments reports

| Number                                                         | What it is                                  |
| -------------------------------------------------------------- | ------------------------------------------- |
| [MRR](/sources/dodopayments/mrr)                               | Active subscriptions, normalised to a month |
| [Total revenue](/sources/dodopayments/revenue)                 | Every succeeded payment in the window       |
| [One-time sales](/sources/dodopayments/one-time-sales)         | Payments not tied to a subscription         |
| [Active subscribers](/sources/dodopayments/active-subscribers) | Status `active` right now                   |
| [Recent payments](/sources/dodopayments/recent-payments)       | The last ten succeeded payments             |

The split between total revenue and one-time sales is the pair worth
placing. Recurring revenue is a book that carries into next month. A one-time
sale is money that has to be earned again. A flat total can hide a collapse
in one covered by a good week of the other.

## Live and test mode

Dodo Payments runs test and live on separate hosts. The connector asks which
mode your key belongs to, because a test key against the live host returns an
authentication error rather than an empty account.
[What the Dodo Payments connector asks for](/sources/dodopayments).

Your API key is encrypted on the server with a key unique to that one
connection, and bound to your account and the provider so a row copied
elsewhere does not decrypt. The Mac app never holds it.

## Alongside everything else

Revenue also comes from [Stripe](/sources/stripe), [Polar](/sources/polar),
[Paddle](/sources/paddle), [Lemon Squeezy](/sources/lemonsqueezy) and
[RevenueCat](/sources/revenuecat). Analytics from
[Plausible](/sources/plausible) and [PostHog](/sources/posthog). Search from
[Search Console](/sources/google-search-console). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year with every connector included.
[Download Notch Metrics](/download).
