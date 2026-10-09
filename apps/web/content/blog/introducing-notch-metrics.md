---
title: Introducing Notch Metrics
description: Revenue, MRR and subscribers in the MacBook notch. Hover to look, move away and it is gone. No dock icon, no menu bar, no dashboard to open.
date: 2026-09-22
author: Notch Metrics
tags: [product, launch]
---

Every founder I know has the same tab open somewhere: a Stripe dashboard, a
Baremetrics chart, a spreadsheet pulling from three places at once. It gets
checked twelve times a day and it costs something every time — a context
switch, a tab, five seconds of loading, and then the slow drift from "what is
MRR" into "let me just look at churn by cohort".

The number was never the problem. Getting to it was.

## The notch is the right amount of screen

A MacBook notch is a few hundred pixels of glass that every Mac app pretends
is not there. It sits above the menu bar, dead centre, in the exact place your
eyes already pass through on the way to anything else. It is too small to hold
a dashboard, which is precisely why it is the right place to hold a number.

Notch Metrics puts your widgets there. Collapsed, it is a thin strip: today's
revenue, MRR, active subscribers, whatever you chose. Hover, and it expands to
the full set. Move the cursor away and it is gone — not minimised, not behind
a toggle. Gone.

There is no dock icon and nothing in the menu bar. The app has exactly one
surface, and that surface only exists while you are looking at it.

## Connect once, on the web

Your API keys never touch your Mac. When you connect a service, the app mints
a short-lived link and opens your browser; you paste the key, or authorise us
over OAuth, and the credential goes straight into our API encrypted with a key
unique to that one connection. The Mac app only ever receives numbers.

That is a deliberate split. A desktop app holding a live Stripe secret key is
a laptop you cannot lose, and people lose laptops.

Revenue comes from Stripe, Polar, Paddle, Dodo Payments, Lemon Squeezy and
RevenueCat. Product analytics from PostHog and Google Analytics. Developer
numbers from GitHub. Each one reports in its own currency and we convert on
the way out, so a notch showing three providers shows one total.

## When a provider does not have your number

Some numbers do not come from a SaaS product. Rows in a Postgres table, a
count from an internal admin API, visitors from a self-hosted analytics box.

For those there are custom metrics: one JavaScript module on your own machine
that returns a number. The code, the keys and the results stay local — the
runner has no `fetch`, only a hardened HTTP helper bound to hostnames you
listed, and secrets live in the macOS Keychain. You can write one by hand, or
point Claude at our [MCP server](https://www.npmjs.com/package/notch-metrics-mcp)
and describe the number you want.

## Get it

Notch Metrics runs on Apple silicon, macOS 14 and later, with a seven-day
trial and no card up front. [Download it](/download), connect one service, and
close the tab you have had open since 2023.
