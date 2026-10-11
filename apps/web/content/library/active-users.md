---
title: "What are active users?"
description: "DAU, WAU and MAU are de-duplicated counts, which is why weekly is never the sum of seven dailies. What active means, and who decides."
date: 2026-10-11
author: Notch Metrics
tags: [active-users, analytics, glossary]
kind: glossary
term: Active users
faq:
  - question: What is the difference between DAU, WAU and MAU?
    answer: >-
      The period each de-duplicates over: one day, seven days and thirty days.
      They are not multiples of each other, because somebody active on three
      days in a week is one weekly active user and three daily ones.
  - question: Why is my weekly active user count lower than the sum of daily counts?
    answer: >-
      Because active users is de-duplicated across the whole period. The sum of
      seven daily counts is inflated by exactly how much your users come back,
      which is the retention you were measuring separately.
  - question: What is a good DAU over MAU ratio?
    answer: >-
      It depends entirely on the product. A messaging app lives above 0.5, a
      business tool sits around 0.2 to 0.3, and something people genuinely open
      once a month is at 0.05 and is not broken. The ratio is useful mainly for
      comparing you against yourself over time.
  - question: What counts as active?
    answer: >-
      Whatever you decided. Opening the app is the loosest definition and the
      default in most tools. Performing a meaningful action is the honest one
      and requires defining what that is. If your app sends a heartbeat on a
      timer, everybody with it installed is active forever.
  - question: Do active users count devices or people?
    answer: >-
      Depends on the tool and the setting. The same human on a phone and a
      laptop is two users if you count device identifiers and one if you count a
      resolved person after identity merging. A number that silently switches
      between the two produces a step in the chart that was never behaviour.
---

**Active users is the number of distinct people who did something in a
period.** The two words doing the work are "distinct" and "something", and
both are decisions rather than facts.

## De-duplication, and the arithmetic everybody gets wrong

Active users is de-duplicated across whatever period it covers. Somebody who
used your product on three days in a week is **one** weekly active user and
three daily active users.

So:

```
WAU  !=  sum(DAU for 7 days)
MAU  !=  sum(DAU for 30 days)
```

The sum is always larger, and it is inflated by exactly how much your users
come back, which is the retention you were presumably measuring separately.

This is why a daily chart's bars never add up to the weekly headline above
them. That is correct. Any tool whose bars do add up is showing you daily
actives seven times rather than weekly actives once.

If you want both, that is two queries.

## DAU over MAU is the stickiness ratio

The standard use of the pair. A product with 3,000 DAU and 10,000 MAU has a
ratio of 0.3, meaning the average user shows up about nine days a month.

Rough benchmarks worth knowing and not trusting: a messaging product lives
above 0.5, a business tool sits around 0.2 to 0.3, and something you open
once a month is at 0.05 and is not broken, it is just that kind of product.

The ratio is useful because it is dimensionless. It compares you to yourself
across growth, which raw counts do not.

## "Active" is whatever you decided

This is the part no benchmark can fix.

**Opened the app** is the loosest definition and the one most tools default
to. It counts somebody who launched your product, looked at it, and did
nothing.

**Performed a meaningful action** is the honest one and it is work. You have
to define what a meaningful action is, and that definition is the product
strategy.

**Was reachable** is the accidental one. If your app sends a heartbeat event
on a timer, everybody with it installed is active forever, and your DAU is a
measure of installs.

A team that quietly moves from the second to the first gets a flattering
chart and loses the ability to compare against last quarter.

## Devices or people

A second decision. Most analytics tools distinguish a device identifier from
a resolved person after identity merging.

Count devices and the same human on a phone and a laptop is two active users.
Count people and they are one. Neither is wrong, but a number that silently
changed from one to the other, usually during an authentication change, is a
step in the chart that was never behaviour.

## Active users in Notch Metrics

Four connectors report it, each using the provider's own de-duplication:
[PostHog](/sources/posthog/active-users),
[Amplitude](/sources/amplitude/active-users),
[Google Analytics](/sources/google-analytics/active-users) and
[RevenueCat](/sources/revenuecat/active-users).

Each page says what that provider counts. The RevenueCat one is worth a
special look: its window is fixed at 28 days by RevenueCat and ignores
whatever range the widget is set to, which the page states rather than
letting a control appear to work when it does not.

[How to query active users from the PostHog API](/blog/query-active-users-from-the-posthog-api)
