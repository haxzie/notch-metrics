---
title: "Introducing Notch Metrics"
description: "Revenue, MRR and subscribers in the MacBook notch. Hover to look, move away and it is gone. No dock icon, no menu bar, no dashboard to open."
date: 2026-09-22
updated: 2026-10-11
author: Notch Metrics
tags: [product, launch]
faq:
  - question: What is Notch Metrics?
    answer: >-
      Notch Metrics is a macOS app that puts business numbers in the MacBook
      notch. Revenue, MRR, subscribers and more sit in the camera housing.
      Hover to expand them, move away and the notch looks untouched. It runs on
      Apple silicon, macOS 14 and later.
  - question: Which services does Notch Metrics connect to?
    answer: >-
      Fourteen connectors are live. Revenue comes from Stripe, Polar, Paddle,
      Dodo Payments, Lemon Squeezy and RevenueCat, sales from Shopify,
      analytics from PostHog, Plausible, Amplitude and Google Analytics, search
      from Google Search Console, video from YouTube, and repository numbers
      from GitHub.
  - question: Does Notch Metrics store my Stripe API key on my Mac?
    answer: >-
      No. You connect a service on the web, and the credential is encrypted
      with a key unique to that one connection. The Notch Metrics server calls
      Stripe and hands your Mac a normalised number. The Mac app never holds a
      provider key.
  - question: How much does Notch Metrics cost?
    answer: >-
      $14 a month, or $79 a year. Every connector is included on both plans,
      with no per-integration charge. The seven-day trial needs no card.
  - question: Can Notch Metrics show a number that has no connector?
    answer: >-
      Yes. Write a custom metric: one JavaScript module that returns a number,
      running on your own Mac with its secrets in the Keychain. A coding agent
      can write it for you over the Notch Metrics MCP server.
---

Every founder keeps the same tab open somewhere. A Stripe dashboard, a
Baremetrics chart, a spreadsheet pulling from three places at once. It gets
checked twelve times a day, and every check costs a context switch, a tab,
five seconds of loading, and then the slow drift from "what is MRR" into "let
me just look at churn by cohort".

The number was never the problem. Getting to it was.

## Why put metrics in the MacBook notch?

A MacBook notch is a few hundred pixels of glass that every Mac app pretends
is not there. It sits above the menu bar, dead centre, in the exact place your
eyes already pass through on the way to anything else. It is too small to hold
a dashboard. That is what makes it the right place to hold a number.

Notch Metrics puts your widgets there. Collapsed, it is a thin strip: today's
revenue, MRR, active subscribers, whatever you chose. Hover, and it expands to
the full set. Move the cursor away and it folds back to the shape it had.

There is no dock icon and nothing in the menu bar. The app has one surface,
and that surface exists only while you are looking at it.

## Connect once, on the web

Your API keys never touch your Mac. Connecting a service opens your browser
through a short-lived link. You paste the key, or approve an OAuth prompt, and
the credential goes into our API encrypted with a key unique to that one
connection. The Mac app receives numbers.

That split is deliberate. A desktop app holding a live Stripe secret key is a
laptop you cannot afford to lose, and people lose laptops.

Revenue comes from Stripe, Polar, Paddle, Dodo Payments, Lemon Squeezy and
RevenueCat. Sales come from Shopify. Product analytics come from PostHog,
Plausible, Amplitude and Google Analytics. Search comes from Google Search
Console, video from YouTube, repository numbers from GitHub. Each provider
reports in its own currency, and the conversion happens on the way out, so a
notch showing three providers shows one total.

[Every source, and every number each one reports](/sources).

## When a provider does not have your number

Some numbers do not come from a SaaS product. Rows in a Postgres table, a
count from an internal admin API, visitors from a self-hosted analytics box.

Those become custom metrics: one JavaScript module on your own machine that
returns a number. The code, the keys and the results stay local. The runner
has no `fetch`, only a hardened HTTP helper bound to the hostnames you listed,
and secrets live in the macOS Keychain. Write one by hand, or point Claude at
our [MCP server](https://www.npmjs.com/package/notch-metrics-mcp) and describe
the number you want.

A custom metric is contained, not sandboxed. It names the hosts it may reach
and nothing else is reachable, but it runs as you, like a script you wrote.
Read what your agent writes.

## Get it

Notch Metrics runs on Apple silicon, macOS 14 and later. Seven days of
everything, with no card. [Download it](/download), connect one service, and
close the tab you have had open since 2023.
