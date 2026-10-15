---
title: "Amplitude active users on your Mac"
description: "Active users, new users and events from Amplitude, in the MacBook notch. Hover the camera housing to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [amplitude, analytics, mac]
faq:
  - question: How do I see Amplitude active users on my Mac?
    answer: >-
      Install Notch Metrics, connect Amplitude on the web with an API key, a
      secret key and your project region, and place the active users widget in
      the MacBook notch.
  - question: Why do the Amplitude widgets have no hourly option?
    answer: >-
      Because the Amplitude Dashboard REST API serves daily, weekly and monthly
      intervals and offers no hourly one. Splitting a day into twenty-four equal
      pieces would be inventing resolution the API never returned.
  - question: Does Notch Metrics support Amplitude EU?
    answer: >-
      Yes. The connector asks which region your project is in, because Amplitude
      runs US and EU data centres and a key pair from one fails against the
      other with an error that reads like bad credentials.
  - question: Why do Amplitude daily bars not add up to the weekly figure?
    answer: >-
      Because active users is de-duplicated across the whole window. One person
      active on three days is one user and three bars, so a weekly figure is
      smaller than the sum of seven daily ones.
  - question: Why does Amplitude show a letter instead of a logo?
    answer: >-
      Because no vendored brand mark exists for it. Notch Metrics shows a
      lettermark rather than approximating a logo, on the grounds that an
      approximated logo looks like a bug and a lettermark looks like a choice.
---

Amplitude is built for asking hard questions. Most days you have one easy
question, and loading a product analytics suite to answer it is the wrong
shape of effort.

## How do you watch Amplitude without opening it?

Notch Metrics puts the headline figures in the MacBook notch. Collapsed, a
thin strip. Hover the camera housing and it expands over whatever you were
doing. Move away and it folds back to the shape it had.

## What Amplitude reports

| Number                                          | What it is                             |
| ----------------------------------------------- | -------------------------------------- |
| [Active users](/sources/amplitude/active-users) | Anyone who did anything, de-duplicated |
| [New users](/sources/amplitude/new-users)       | First seen in the window               |
| [Events](/sources/amplitude/events)             | Every event recorded, of every type    |

Three numbers rather than thirty, and that is the point. The notch is a few
hundred pixels of glass. If you need a cohort breakdown, Amplitude is still
the right place to go.

## Daily buckets, with no hourly option

Amplitude's Dashboard REST API serves daily, weekly and monthly intervals.
There is no hourly one, so [the widgets](/sources/amplitude/active-users)
offer none rather than manufacturing it by splitting a day into twenty-four
equal pieces.

A sparkline that invents its own resolution is worse than a coarser one.

## Why the bars do not add up

Active users is de-duplicated across the whole window, so one person active
on three days is one user and three bars. A weekly figure is not the sum of
seven daily figures.

That is Amplitude's own behaviour and it is the correct one. It is worth
knowing before you check the arithmetic.

## Connecting

An API key, a secret key and your project's region. Amplitude runs US and EU
data centres and a key pair from one returns an error against the other,
which reads like bad credentials rather than a wrong region. The connector
asks, and says so when it fails.
[What the Amplitude connector asks for](/sources/amplitude).

Both keys are encrypted on the server with a key unique to that connection,
so the Mac app never holds them.

## Beta, and the mark

The Amplitude connector is marked beta on [its page](/sources/amplitude). It
connects and returns figures today. It also has no vendored brand mark, so it
shows a lettermark rather than an approximated logo, which is a deliberate
choice: an approximated logo looks like a bug and a lettermark looks like a
decision.

## Alongside everything else

Revenue from [Stripe](/sources/stripe), traffic from
[Plausible](/sources/plausible) and
[Google Analytics](/sources/google-analytics), product analytics from
[PostHog](/sources/posthog). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
