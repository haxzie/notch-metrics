---
title: "Plausible visitors in your MacBook notch"
description: "Unique visitors, pageviews, sessions and bounce rate from Plausible, in the strip of glass around your Mac's camera. No tab to open."
date: 2026-10-11
author: Notch Metrics
tags: [plausible, analytics, mac]
faq:
  - question: How do I see Plausible visitors on my Mac?
    answer: >-
      Install Notch Metrics, connect Plausible on the web with an API key and
      your site id, and place the visitors widget in the MacBook notch. Hover
      the camera housing and the figure is there.
  - question: How does Plausible count unique visitors without cookies?
    answer: >-
      By hashing the IP address with the user agent and a daily rotating salt.
      Nothing is stored on the device. Because the salt rotates daily, somebody
      who visits on two days counts as two visitors over a two-day window.
  - question: Which timezone do Plausible daily figures use?
    answer: >-
      The timezone configured on the Plausible site, not the one your Mac is set
      to. That keeps the notch and the Plausible dashboard agreeing about which
      day a number belongs to.
  - question: Does Notch Metrics work with self-hosted Plausible?
    answer: >-
      The built-in connector targets Plausible Cloud. For a self-hosted
      instance, write a custom metric: one JavaScript module that declares your
      own host and runs on your Mac.
  - question: Is my Plausible API key stored on my Mac?
    answer: >-
      No. It is encrypted on the server with a key unique to that one
      connection. The Notch Metrics server calls Plausible and sends your Mac a
      normalised number.
---

Plausible is a single page that loads instantly and tells you everything. It
is still a page, and you still have to go to it.

## How do you watch Plausible without the dashboard?

Notch Metrics puts the figures in the MacBook notch. Collapsed, a thin strip.
Hover the camera housing and it expands over whatever you were doing. Move
away and it folds back to the shape it had.

## What Plausible reports

| Number                                         | What it is                                |
| ---------------------------------------------- | ----------------------------------------- |
| [Unique visitors](/sources/plausible/visitors) | Distinct people, counted without a cookie |
| [Pageviews](/sources/plausible/pageviews)      | Every page load, repeats included         |
| [Sessions](/sources/plausible/sessions)        | Visits started in the window              |
| [Bounce rate](/sources/plausible/bounce-rate)  | Sessions with one pageview, as a fraction |

## The cookieless count, and what it costs

Plausible identifies a visitor by hashing the IP address with the user agent
and a daily rotating salt. No cookie, nothing stored on the device, and in
most of Europe no consent banner.

The trade is worth understanding. The hash rotates daily, so somebody who
visits on Monday and again on Tuesday is two visitors over a two-day window,
not one. Over long windows a unique visitor count sits closer to a visit
count than to a count of people.

That is a privacy decision rather than a measurement failure, and it is the
right one. It just means the number does not mean quite what the label says.

## Timezone is the site's

Daily buckets follow the timezone set on the Plausible site, not on your Mac.
That keeps the notch and your Plausible dashboard agreeing, which matters
more than agreeing with your laptop clock.

## Connecting

A Plausible API key and the site id, which is the domain as Plausible knows
it. [What the Plausible connector asks for](/sources/plausible).

The key is encrypted on the server with a key unique to that one connection,
so the Mac app never holds it. The connector is marked beta: it connects and
returns figures, and the edges are still being worked on.

## Self-hosted Plausible

The connector targets Plausible Cloud. A self-hosted instance lives on your
own domain, which the hosted connector does not reach. If that is you, a
[custom metric](/blog/writing-a-custom-metric) covers it: one JavaScript
module declaring your host, running on your own Mac.

## Alongside everything else

Revenue from [Stripe](/sources/stripe) and [Polar](/sources/polar), search
from [Search Console](/sources/google-search-console), product analytics from
[PostHog](/sources/posthog). [Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $14 a month
or $79 a year. [Download Notch Metrics](/download).
