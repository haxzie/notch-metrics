---
title: "Baremetrics alternatives"
description: "Baremetrics is priced on the revenue it tracks. Four alternatives, what each actually replaces, and prices read off their own pages."
date: 2026-10-11
author: Notch Metrics
tags: [baremetrics, alternatives, saas]
kind: alternatives
verifiedOn: 11 October 2026
faq:
  - question: How much does Baremetrics cost in 2026?
    answer: >-
      Free while it tracks up to $180K ARR. Launch is $49 a month to $360K ARR,
      Growth starts at $69 a month to $3.6M ARR, and Scale starts at $409 a
      month above that. Payment Recovery and Cancellation Insights are $129 a
      month each. Annual billing can take up to 35% off. Checked 11 October
      2026.
  - question: Is there a free alternative to Baremetrics?
    answer: >-
      For the MRR figure, yes. MRRDock is free and MIT licensed and reads seven
      payment platforms into one menu bar total. The Stripe Dashboard is also
      free and shows MRR, churn and subscriber counts natively. Neither does
      cohort analysis, LTV or forecasting.
  - question: What does Baremetrics do that a menu bar app cannot?
    answer: >-
      Cohort retention, LTV by segment, scenario planning, failed-payment
      recovery and cancellation feedback. Those need stored history and a full
      screen. A glance tool answers what your MRR is right now and deliberately
      stops there.
  - question: Why is Baremetrics priced on my revenue?
    answer: >-
      Because it is priced by the annual recurring revenue it tracks rather than
      by seats, so you can invite your whole team without the price changing. As
      your tracked revenue crosses a band, the plan steps up.
  - question: Can Notch Metrics replace Baremetrics?
    answer: >-
      For the daily glance, yes, and across more than revenue: fourteen
      connectors covering payments, analytics, search, video and GitHub, for $14
      a month or $79 a year. For cohort analysis, LTV and forecasting, no. Those
      are a different job and the notch is a few hundred pixels.
---

## TL;DR

| Alternative        | Price                               | Replaces                                  |
| ------------------ | ----------------------------------- | ----------------------------------------- |
| **Notch Metrics**  | **$14/mo or $79/yr**                | The daily glance, across fourteen sources |
| MRRDock            | Free, MIT licensed                  | The MRR figure                            |
| Stripe Dashboard   | Free                                | The detail and the source of truth        |
| Baremetrics itself | Free to $180K ARR, then from $49/mo | Cohorts, LTV, forecasting                 |

Prices checked on 11 October 2026, on each vendor's own pricing page.

## What does Baremetrics actually cost?

Worth getting right before looking for an alternative, because the answer has
changed and most third-party articles quote old figures.

Baremetrics is free while it tracks up to $180K ARR. Above that, Launch is
$49 a month to $360K ARR, Growth starts at $69 a month to $3.6M ARR, and
Scale starts at $409 a month above that. Pricing is set by the annual
recurring revenue it tracks, not by seats, so inviting your team costs
nothing. Annual billing can take up to 35% off, and Launch is month to month
only.

Two add-ons sit on top of any plan at $129 a month each: Payment Recovery,
which can instead be billed at 10% of recovered revenue, and Cancellation
Insights.

So the honest summary is that Baremetrics is free for a small business and
scales with success. People look for alternatives for two different reasons,
and they need different answers.

## Which problem are you solving?

**"It costs too much at my revenue."** You want something cheaper that still
does analysis. That is a narrow field, and the real answer is usually that
you do not need the analysis as often as you are paying for it.

**"I only ever look at one number."** You want a glance tool, and you have
been paying for a cohort engine to answer a question a menu bar could answer.
This is by far the more common case.

---

## 1. Notch Metrics

If what you actually do with Baremetrics is open it, read MRR, and close it,
this is the replacement.

Notch Metrics puts your numbers in the MacBook notch, the strip of glass
around the camera. Hover and they are there. Move away and the notch looks
untouched. No dock icon, no menu bar item, no tab.

It goes wider than revenue, which is the part Baremetrics does not do at all.
[Stripe](/sources/stripe), [Polar](/sources/polar),
[Paddle](/sources/paddle), [Lemon Squeezy](/sources/lemonsqueezy),
[Dodo Payments](/sources/dodopayments),
[RevenueCat](/sources/revenuecat) and [Shopify](/sources/shopify) for money,
then [Plausible](/sources/plausible), [PostHog](/sources/posthog) and
[Google Analytics](/sources/google-analytics) for traffic,
[Search Console](/sources/google-search-console) for search, and
[GitHub](/sources/github) and [YouTube](/sources/youtube) besides. Fourteen
connectors, all included, no per-integration charge.

Your provider keys never reach your Mac. They are encrypted on the server
with a key unique to each connection, and the app receives normalised
numbers.

What it does not do is cohort analysis, LTV or forecasting. That is
deliberate: the notch is a few hundred pixels and a cohort chart does not fit
in it.

**Price.** $14 a month or $79 a year, every connector included. Seven-day
trial, no card.
**Requires.** Apple silicon, macOS 14 or later.

[Download Notch Metrics](/download) · [Every source](/sources)

## 2. MRRDock

Free and MIT licensed, and the cheapest honest answer if the only number you
want is MRR.

It reads Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo Payments and
Gumroad, converts them into one currency, and shows the total in the menu
bar. No account, no server, keys in the macOS Keychain, GET requests only.

Its MRR rules are published, which is more than most: yearly divided by
twelve, percentage coupons applied, usage-based prices flagged rather than
guessed. Compared against Baremetrics it has no history analysis and no
recovery tooling, and its keys sit on your laptop rather than a server.

**Price.** Free, MIT licensed.
**Requires.** macOS 14 or later.

## 3. The Stripe Dashboard

Free, and it already has most of what people check Baremetrics for. Stripe
Billing shows MRR, churn and subscriber counts natively, and Sigma will
answer almost any question in SQL if you are willing to write it.

What Stripe will not do is span providers. If your money arrives through
Stripe and RevenueCat and a Shopify store, Stripe knows about a third of your
business, which is the gap every tool on this page exists to fill.

**Price.** Free. Sigma is billed separately on query volume.
**Requires.** A browser.

## 4. Staying on Baremetrics

Worth saying because it is often right.

If you genuinely use cohort retention, LTV by segment, scenario planning or
dunning recovery, nothing cheaper replaces them properly, and the free tier
to $180K ARR means a lot of businesses are not paying anything yet.

The pattern that actually works for most founders is both: Baremetrics open
once a month for the questions that need history, and something glanceable
for the question you ask twenty times a day.

## So which one

**You open Baremetrics to read MRR and close it.** Notch Metrics, and get
your traffic and search numbers in the same glance.

**You want that for free and only care about MRR.** MRRDock.

**You are under $180K ARR.** Baremetrics is free. Stay.

**You run cohort and LTV analysis properly.** Keep Baremetrics and add a
glance tool for the daily number.

[See what Notch Metrics costs](/#pricing)
