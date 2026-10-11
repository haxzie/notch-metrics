---
title: "How to count new users in GA4"
description: "New users depends on a cookie, and consent mode changes what GA4 can see. What the number counts and when it quietly stops being comparable."
date: 2026-10-11
author: Notch Metrics
tags: [google-analytics, ga4, api]
pillar: ga4-visitors-in-your-notch
faq:
  - question: What is the GA4 metric for new users?
    answer: >-
      newUsers. It counts users who triggered first_visit on web or first_open
      in an app during the window, which GA4 fires when it sees a client with no
      existing analytics cookie or app instance id.
  - question: Why are my GA4 new users higher than my real signups?
    answer: >-
      Because new means no cookie rather than never been here. Cleared cookies,
      a second device, Safari's Intelligent Tracking Prevention capping cookie
      lifetime, and consent-mode modelling all create a new user who is not a
      new person.
  - question: Does Safari ITP affect GA4 new user counts?
    answer: >-
      Yes, and permanently. ITP caps client-side cookie lifetime, so a Safari
      visitor returning after that window is counted as new again. On a consumer
      site with heavy Safari traffic this inflates new users materially.
  - question: Can I sum daily GA4 new users for a weekly total?
    answer: >-
      Not exactly. newUsers de-duplicates within the window, so summing seven
      daily rows overcounts. The gap is smaller than for active users because a
      person can only be new once, but window boundaries and modelling still
      move it.
  - question: What should I read alongside GA4 new users?
    answer: >-
      Active users. New rising while active stays flat means acquisition is
      working and nothing is sticking. A new-user chart alone rewards whoever
      buys the most traffic.
---

## The call

```json
{
  "dateRanges": [{ "startDate": "2026-10-01", "endDate": "2026-10-07" }],
  "dimensions": [{ "name": "date" }],
  "metrics": [{ "name": "newUsers" }]
}
```

`newUsers`, not `ga:newUsers`. The UA prefix is gone.

## What GA4 means by new

A user who triggered `first_visit` on web, or `first_open` in an app, during
the window. GA4 fires that event when it sees a client with no existing
analytics cookie or app instance id.

So "new" means "no cookie", which is not the same as "never been here
before".

## Four things that create a new user who is not

**Clearing cookies.** The same person, back tomorrow, is new.

**A different browser or device.** Unless your property has User-ID
configured and the person is signed in, a laptop and a phone are two users
and both were new once.

**Safari and ITP.** Intelligent Tracking Prevention caps client-side cookie
lifetime, so a returning Safari visitor past the window is new again. On a
consumer site with heavy Safari traffic this inflates new users materially
and permanently.

**Consent mode.** With consent denied, GA4 models behaviour rather than
observing it. The number is an estimate, and whether it is modelled depends
on your consent rates, which change when you change your banner.

None of those are bugs. They are the limits of what a cookie can know, and
they mean a new-user trend is comparable against itself only while your
consent setup and traffic mix hold still.

## Totals, again

`newUsers` de-duplicates within the window. Somebody whose `first_visit`
lands on Tuesday is new once in the week and once on Tuesday, so summing
seven daily rows overcounts the weekly figure.

Ask for the total explicitly with `metricAggregations: ["TOTAL"]`, or drop
the `date` dimension.

In practice the gap is smaller here than for active users, because a person
can only be new once in their life. It is not zero, because window boundaries
and modelling both move.

## New against active

The pair that means something.

- **New flat, active rising.** Retention improving.
- **New rising, active flat.** Acquisition working, nothing sticking.
- **New rising, active falling.** Paying for traffic that leaves faster than
  it arrives.

A new-user chart alone rewards whoever buys the most traffic, which is rarely
the outcome anybody wanted to incentivise.

## First-time users against new users

GA4 also exposes `firstTimePurchasers` and, in some contexts, a `newVsReturning`
dimension. The dimension is a useful cross-check: a breakdown by it against a
`sessions` metric tells you how much of your traffic is returning, which is
the retention question the new-user count only half answers.

## Thresholding

Rows with very few users are withheld, particularly where demographics are
involved. A breakdown of new users by country can add up to less than the
total, and a missing country is not a country with zero visitors.

## In the notch

Notch Metrics reports
[GA4 new users](/sources/google-analytics/new-users) in the MacBook notch,
daily, weekly or monthly, with a sparkline and a comparison against the
previous window.

Place it beside
[active users](/sources/google-analytics/active-users) and
[sessions](/sources/google-analytics/sessions).
[Everything Google Analytics reports](/sources/google-analytics), or
[download Notch Metrics](/download).
