---
title: "Best Stripe MRR trackers for Mac"
description: "A ranked look at the Mac apps that keep your Stripe MRR one glance away, with prices read off each vendor's own page."
date: 2026-10-11
author: Notch Metrics
tags: [mrr, mac, comparison]
kind: comparison
verifiedOn: 11 October 2026
faq:
  - question: What is the best way to track Stripe MRR on a Mac?
    answer: >-
      Put it somewhere you already look. Notch Metrics shows Stripe MRR in the
      MacBook notch for $14 a month or $79 a year, MRRDock shows it in the menu
      bar for free under an MIT licence, and Orbl puts it on your wallpaper with
      a $39 one-time Premium purchase. All three read the same Stripe account.
  - question: Is there a free Stripe MRR tracker for Mac?
    answer: >-
      Yes. MRRDock is free and MIT licensed, and reads Stripe, RevenueCat,
      Paddle, Lemon Squeezy, Polar, Dodo Payments and Gumroad into one menu bar
      figure. Orbl's base app is free, though its revenue integrations need the
      $39 Premium purchase. Baremetrics is free while it tracks up to $180K ARR.
  - question: Is it safe to give a Mac app my Stripe key?
    answer: >-
      Use a restricted key with read access to Charges and Subscriptions, which
      cannot move money even if it leaked. Beyond that, ask where the key ends
      up. MRRDock and Orbl keep it in your Mac's Keychain. Notch Metrics never
      sends a key to the Mac at all: it is encrypted on the server and the app
      receives only numbers.
  - question: How much does Baremetrics cost?
    answer: >-
      Baremetrics is free while it tracks up to $180K ARR. Launch is $49 a month
      to $360K ARR, Growth starts at $69 a month to $3.6M ARR, and Scale starts
      at $409 a month above that. Payment Recovery and Cancellation Insights are
      $129 a month each. Prices checked on 11 October 2026.
  - question: Can I track revenue from more than just Stripe?
    answer: >-
      Yes, with several of these. Notch Metrics connects Stripe, Polar, Paddle,
      Dodo Payments, Lemon Squeezy, RevenueCat and Shopify, plus analytics and
      search sources. MRRDock covers seven payment platforms plus any HTTPS
      endpoint of your own.
  - question: Menu bar, notch or wallpaper, which is better?
    answer: >-
      The menu bar is conventional and already crowded, and macOS hides the
      newest items when it runs out of room. A wallpaper is only visible when
      your windows are not. The notch sits in front of everything, always, which
      is why Notch Metrics uses it.
---

## TL;DR

|     | Tool              | Price                               | Where it lives    | Best for                                         |
| --- | ----------------- | ----------------------------------- | ----------------- | ------------------------------------------------ |
| 1   | **Notch Metrics** | **$14/mo or $79/yr**                | The MacBook notch | Several sources, and numbers beyond revenue      |
| 2   | MRRDock           | Free, MIT licensed                  | Menu bar          | One MRR total, open source, no cost              |
| 3   | Orbl              | Free app, Premium $39 once          | Wallpaper         | Revenue in context with the rest of your desktop |
| 4   | Baremetrics       | Free to $180K ARR, then from $49/mo | Browser           | Cohorts, LTV and churn analysis                  |
| 5   | Stripe Dashboard  | Free                                | Browser and phone | The authoritative detail                         |

Prices checked on 11 October 2026, on each vendor's own pricing page.

This is about where your revenue number lives when you are not looking for
it. All five read the same Stripe account. What differs is how much of your
day it costs to see the figure, and what else it can tell you.

## How do you choose an MRR tracker for Mac?

Three questions settle it.

**How many places does your money arrive?** One Stripe account is a solved
problem and almost anything here works. Stripe plus RevenueCat plus a Shopify
store is a different problem, and most tools answer only part of it.

**Do you want revenue, or do you want your numbers?** An MRR tracker shows
MRR. If you also want visitors, search clicks and open issues in the same
glance, that is a wider tool.

**Where does your Stripe key end up?** On your Mac, on somebody's server, or
nowhere because the tool is read-only through a restricted key. All three are
defensible. Knowing which one you chose is not optional.

---

## 1. Notch Metrics

The MacBook notch is a few hundred pixels of glass above the menu bar that
every other Mac app pretends is not there. Notch Metrics puts your numbers
in it. Collapsed, a thin strip. Hover the camera housing and it expands over
whatever you were doing. Move away and it folds back.

There is no dock icon and nothing in the menu bar, which matters more than it
sounds: the menu bar is already full, and macOS hides the newest items when
it runs out of room.

Fourteen connectors, every one included on both plans with no per-integration
charge. [Stripe](/sources/stripe), [Polar](/sources/polar),
[Paddle](/sources/paddle), [Dodo Payments](/sources/dodopayments),
[Lemon Squeezy](/sources/lemonsqueezy), [RevenueCat](/sources/revenuecat) and
[Shopify](/sources/shopify) for money.
[Plausible](/sources/plausible), [PostHog](/sources/posthog),
[Amplitude](/sources/amplitude) and
[Google Analytics](/sources/google-analytics) for traffic.
[Search Console](/sources/google-search-console),
[YouTube](/sources/youtube) and [GitHub](/sources/github) for everything
else.

Keys are the real difference. You connect on the web and the credential is
encrypted with a key unique to that one connection, bound to your account and
the provider. The server calls Stripe and hands your Mac a number, so the Mac
app never holds a Stripe key at all. A lost laptop yields nothing.

And when a number has no connector, a coding agent writes a
[custom metric](/blog/writing-a-custom-metric) over MCP: one JavaScript
module running on your own machine, secrets in the Keychain.

**Price.** $14 a month, or $79 a year. Seven-day trial, no card.
**Requires.** Apple silicon, macOS 14 or later.

[Download Notch Metrics](/download) · [Every source](/sources)

## 2. MRRDock

Free, MIT licensed, and genuinely good at the one thing it does. MRRDock
aggregates MRR from Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo
Payments and Gumroad into a single menu bar figure, converted into one
currency.

It is the only tool here whose source you can read before pasting a Stripe
key into it, which is a real argument. Keys live in the macOS Keychain, it
issues only GET requests, and there is no server or account.

Its arithmetic is documented and conservative: yearly divided by twelve,
percentage coupons applied, fixed-amount coupons deliberately not applied,
usage-based prices flagged rather than guessed. That last choice is the right
one and most tools do not make it.

Where Notch Metrics differs is scope. MRRDock answers "what is my MRR right
now" and stops there, by design. It will not tell you your Search Console
clicks or your Shopify orders, and its keys sit on the laptop rather than on
a server.

**Price.** Free, MIT licensed, no paid tier.
**Requires.** macOS 14 or later, Apple silicon or Intel.

## 3. Orbl

Orbl puts revenue on your wallpaper rather than in the menu bar, alongside
weather, focus and a GitHub contribution graph. It is a different idea and it
suits people who want their numbers in context rather than as a figure in a
strip.

It is local: read-only keys in the macOS Keychain, called directly from your
Mac, no server and no account. Premium unlocks the revenue integrations and
is a one-time purchase, which is a fair point to make about a category full
of subscriptions.

The trade is visibility. A wallpaper is behind your windows, and most people
with a Mac full of windows see their desktop rarely. The notch is in front of
everything, always, which is the whole reason Notch Metrics uses it.

**Price.** Free app. Premium $39 as a one-time purchase, listed as a launch
price rising to $49.
**Requires.** macOS.

## 4. Baremetrics

The analytics tier rather than the glance tier. Baremetrics does cohorts,
LTV, churn analysis, forecasting, failed-payment recovery and cancellation
insights, which is a different job from showing you a number.

It is free while it tracks up to $180K ARR for you, which makes it a
genuinely reasonable starting point. Above that it is priced on the revenue
it tracks: Launch is $49 a month to $360K ARR, Growth starts at $69 a month
to $3.6M ARR, and Scale starts at $409 a month above that. Payment Recovery
and Cancellation Insights are $129 a month each on top, or 10% of recovered
revenue for the first.

Your billing data lives on their servers, which is the price of the analysis.
A tool that computes cohorts has to hold the history.

Use it for the quarterly question. Use something on this page for the daily
one.

**Price.** Free to $180K ARR, then from $49/month, scaling with tracked
revenue. Annual billing can take up to 35% off.
**Requires.** A browser.

## 5. The Stripe Dashboard

Free, authoritative, and the thing every other tool on this page reads from.
The mobile app sends a notification on each payment, which is the closest
Stripe itself gets to a glance.

It is also a browser tab that takes several seconds to load, which is the
entire reason this category exists. Keep it for the detail.

**Price.** Free.
**Requires.** A browser, or the Stripe iOS or Android app.

## Also in this category

Three more Mac apps come up regularly and their current prices were not
verified on the check date above, so none are quoted here. **MRRTracker** is
a focused single-number menu bar app. **IndieBar** packs several revenue
metrics into one menu bar dropdown. **CatBar** is purpose-built for
RevenueCat and is the natural pick if your revenue is app subscriptions
rather than Stripe.

## So which one

**You ship on one platform and want to spend nothing.** MRRDock. It is free,
it is open source, and for a single Stripe account it does exactly the job.

**You want revenue and everything else in one glance.** Notch Metrics. The
fourteen connectors are the point, and so is the fact that your Stripe key
never reaches the laptop.

**You want your desktop to feel calm and informative.** Orbl, if you actually
see your wallpaper.

**You need cohorts and forecasting for a board meeting.** Baremetrics, and
keep a glance tool for the other twenty-nine days of the month.

The honest version is that most people want two: something free or cheap that
answers the daily question without a tab, and something heavier for the
quarterly one.

[See what Notch Metrics costs](/#pricing)
