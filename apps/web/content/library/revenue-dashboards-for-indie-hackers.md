---
title: "Revenue dashboards for indie hackers"
description: "A buyer's guide for solo founders. What to track, how often to look, and which tool fits a business run by one person."
date: 2026-10-11
author: Notch Metrics
tags: [indie-hackers, revenue, guide]
kind: comparison
verifiedOn: 11 October 2026
faq:
  - question: What numbers should an indie hacker track?
    answer: >-
      Four categories cover almost everything: money as MRR or revenue, demand
      as visitors, search as clicks and impressions, and one product-health
      number such as active users or open issues. Only the first is revenue,
      which is why a revenue-only dashboard answers a quarter of the question.
  - question: How often should I check my revenue?
    answer: >-
      As often as you like, once looking costs nothing. The expensive part is
      not the glance, it is the tab, the login and the fifteen minutes you then
      spend on churn by cohort. Reduce the cost to zero and the frequency stops
      mattering.
  - question: What is the best revenue dashboard for a solo founder?
    answer: >-
      It depends on how many places your money arrives. One Stripe account and
      one number: MRRDock, free and open source. Several sources plus traffic
      and search: Notch Metrics, $14 a month or $79 a year with fourteen
      connectors included.
  - question: Do I need a paid analytics tool as an indie hacker?
    answer: >-
      Often not. Baremetrics is free while it tracks up to $180K ARR, which
      covers most indie businesses, and the Stripe Dashboard already shows MRR
      and churn. Pay when you need cohort analysis regularly or when checking
      several sources has become a daily habit.
  - question: How many metrics should I watch?
    answer: >-
      About four. A solo founder's constraint is attention rather than data, and
      a tool showing forty metrics has given you thirty-five chances to spend an
      afternoon on something that was not going to change the outcome.
---

## TL;DR

| If you                                         | Use               | Price                |
| ---------------------------------------------- | ----------------- | -------------------- |
| Take money in one place, want one number       | MRRDock           | Free, MIT            |
| Take money in several places, check constantly | **Notch Metrics** | **$14/mo or $79/yr** |
| Are under $180K ARR and want analysis          | Baremetrics       | Free to $180K ARR    |
| Want the full detail, occasionally             | Stripe Dashboard  | Free                 |

Prices checked on 11 October 2026.

## What should a solo founder actually track?

Fewer numbers than you think, and more kinds of them.

A business run by one person has no reporting layer and no weekly metrics
meeting. The numbers do their work by being glanced at, which means the right
set is the one that fits in a glance and the right frequency is whatever
costs you nothing to check.

Four categories cover almost every indie business:

**Money.** [MRR](/library/mrr) if you sell subscriptions,
[revenue](/sources/stripe/revenue) if you sell one-offs, usually both.

**Demand.** Visitors and where they came from. A revenue number with no
traffic number beside it tells you what happened and never why.

**Search.** [Clicks and impressions](/sources/google-search-console/clicks),
because for most indie products search is the whole acquisition channel and
it moves on a timescale you will miss if you only look monthly.

**Whatever your product's health actually is.** Open issues for a developer
tool. Active users for an app. Subscribers for a channel. This is the one
nobody can pick for you.

Notice that only the first is revenue. A revenue dashboard that is only a
revenue dashboard answers a quarter of the question.

## How often is too often?

The usual advice is to check less. That is almost right and slightly wrong.

The cost of checking is not the looking, it is the loading: the tab, the
login, the chart redraw, and then the fifteen minutes you spend reading churn
by cohort because you were already there.

Reduce the cost to nothing and the frequency stops mattering. A number you
glance at twenty times a day without opening anything has cost you nothing
and taught you the shape of your week. The same number behind a login
twenty times a day has cost you an afternoon.

So: make it free to look, then look as much as you like.

---

## What to use

### Notch Metrics

Built for exactly this shape of business. The numbers live in the MacBook
notch, the strip of glass around the camera. Hover and they are there, move
away and the notch looks untouched. No dock icon, no menu bar item, no tab.

Fourteen connectors, every one included: [Stripe](/sources/stripe),
[Polar](/sources/polar), [Paddle](/sources/paddle),
[Dodo Payments](/sources/dodopayments),
[Lemon Squeezy](/sources/lemonsqueezy), [RevenueCat](/sources/revenuecat),
[Shopify](/sources/shopify), [Plausible](/sources/plausible),
[PostHog](/sources/posthog), [Amplitude](/sources/amplitude),
[Google Analytics](/sources/google-analytics),
[Search Console](/sources/google-search-console),
[YouTube](/sources/youtube) and [GitHub](/sources/github).

That list is the argument. An indie business in 2026 usually has money in two
places, traffic in one, search in another and a repository somewhere, and
every one of those is a separate dashboard.

For anything with no connector, a coding agent writes a
[custom metric](/blog/writing-a-custom-metric) over MCP: one JavaScript
module on your own Mac, secrets in the Keychain.

**Price.** $14/month or $79/year. Seven-day trial, no card.

[Download Notch Metrics](/download)

### MRRDock

If your business genuinely is one Stripe account and one number, this is free
and open source and you should use it. Keys in the Keychain, no server, MIT
licensed, and its MRR rules are published.

**Price.** Free.

### Baremetrics

Free while it tracks up to $180K ARR, which covers most indie businesses
outright. Full subscription analytics, trial insights and segments, in a
browser. Above the threshold it starts at $49 a month and scales with tracked
revenue.

Right for the monthly question. Wrong for the daily one, because it is a tab.

**Price.** Free to $180K ARR, then from $49/month.

### The Stripe Dashboard

Free and authoritative. Keep it for the detail and for anything you need to
be certain about.

**Price.** Free.

## The mistake worth avoiding

Picking tools by how much they can show you.

A solo founder's constraint is attention, not data. The product that shows
you forty metrics has given you thirty-five opportunities to spend an
afternoon on something that was not going to change the outcome.

Pick four numbers. Put them where looking costs nothing. Go back to work.

[See what Notch Metrics costs](/#pricing) · [Every source](/sources)
