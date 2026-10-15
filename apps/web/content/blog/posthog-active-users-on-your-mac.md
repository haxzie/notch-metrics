---
title: "PostHog active users on your Mac"
description: "Active users, events, pageviews and sessions from PostHog, in the MacBook notch. Hover the camera housing to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [posthog, analytics, mac]
faq:
  - question: How do I see PostHog active users on my Mac?
    answer: >-
      Install Notch Metrics, connect PostHog on the web with a personal API key,
      a project id and your cloud region, and place the active users widget in
      the MacBook notch.
  - question: Why do PostHog daily bars not add up to the weekly active user figure?
    answer: >-
      Because active users is de-duplicated across the whole window. One person
      active on three days is one user and three bars. A weekly active count is
      not the sum of seven daily ones.
  - question: Does Notch Metrics use my PostHog project timezone?
    answer: >-
      Yes. Buckets follow the timezone configured on the PostHog project rather
      than your Mac, so the notch and your PostHog dashboards agree about which
      day a number belongs to.
  - question: Does Notch Metrics support PostHog EU cloud?
    answer: >-
      Yes. The connector asks which region your key belongs to, because a US key
      against the EU cloud returns 401 and the other way round, which reads like
      a revoked key rather than a wrong host.
  - question: Is the PostHog connector finished?
    answer: >-
      It is marked beta. It connects and returns active users, new users,
      events, pageviews and sessions today; the edges are still being worked on.
---

PostHog answers almost any question you can phrase. That is its strength and
the reason opening it costs you ten minutes rather than one.

## How do you watch PostHog without opening PostHog?

Notch Metrics puts the headline figures in the MacBook notch. Collapsed, a
thin strip. Hover the camera housing and it expands over whatever you were
doing. Move away and it folds back.

## What PostHog reports

| Number                                        | What it is                                    |
| --------------------------------------------- | --------------------------------------------- |
| [Active users](/sources/posthog/active-users) | People with at least one event, de-duplicated |
| [New users](/sources/posthog/new-users)       | First seen in the window                      |
| [Events](/sources/posthog/events)             | Everything ingested, autocapture included     |
| [Pageviews](/sources/posthog/pageviews)       | `$pageview` events                            |
| [Sessions](/sources/posthog/sessions)         | Sessions started in the window                |

## The de-duplication that explains the chart

Active users is de-duplicated across the whole window. One person active on
three days is one user and three bars, so the bars in the sparkline do not
add up to the headline.

That is correct and it surprises people every time. A weekly active user
count is not the sum of seven daily ones, and any tool whose bars do add up
is reporting daily actives seven times rather than weekly actives once.

## Timezones are your project's

PostHog buckets in the timezone configured on the project, not on your Mac.
That is deliberate: it means the notch and your PostHog dashboards agree, and
two screens in the same company showing different Tuesdays is worse than
being an hour out from your laptop clock.

## Cloud region matters

PostHog runs US and EU clouds and a key from one returns 401 against the
other, which reads like a revoked key. The connector asks which region, and
says so when it fails.
[What the PostHog connector asks for](/sources/posthog).

A personal API key and a project id. The key is encrypted on the server with
a key unique to that connection, so the Mac app never holds it.

## Beta, honestly

The PostHog connector is marked beta on [its page](/sources/posthog). It
connects and returns figures; the edges are still being worked on.

## Alongside everything else

Revenue from [Stripe](/sources/stripe) and [Polar](/sources/polar), traffic
from [Plausible](/sources/plausible) and
[Google Analytics](/sources/google-analytics), search from
[Search Console](/sources/google-search-console). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $9 a month
or $49 a year. [Download Notch Metrics](/download).
