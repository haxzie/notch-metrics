---
title: "What is click-through rate?"
description: "CTR is clicks divided by impressions. Why a falling CTR is often good news, and why it must never be read without volume beside it."
date: 2026-10-11
author: Notch Metrics
tags: [ctr, seo, glossary]
kind: glossary
term: Click-through rate
faq:
  - question: How is click-through rate calculated?
    answer: >-
      Clicks divided by impressions over the period. Use the period totals
      rather than averaging the daily rates, which would weight a day with ten
      impressions equally with a day of ten thousand.
  - question: Is a falling CTR bad?
    answer: >-
      Often not. CTR falls when a page starts ranking for broader terms, so more
      impressions at worse positions convert at a lower rate while total clicks
      rise. It also falls when Google answers the query on the results page or a
      rich result sits above you.
  - question: When is a falling CTR a real problem?
    answer: >-
      When impressions and average position are both steady and clicks fall.
      That isolates the one variable you control, which is what your result
      says. A page at position two with low CTR is usually a title or
      description problem.
  - question: Why does my CTR headline not match the chart?
    answer: >-
      Because each chart point is that day's own ratio and the headline is the
      period's clicks divided by the period's impressions. They are not supposed
      to match.
  - question: Can I compare CTR between two pages?
    answer: >-
      Only alongside their positions. Roughly half the variation in a page's
      search CTR is explained by where it ranks, so comparing two pages' CTRs
      without comparing their positions is nearly worthless.
---

**Click-through rate is clicks divided by impressions.** How often the people
who saw you chose you.

## It is a ratio over the period, not an average of days

The arithmetic trap that applies to every ratio.

```
Right:  total_clicks / total_impressions
Wrong:  mean(daily_clicks / daily_impressions)
```

The weighted version lets a Monday with ten thousand impressions count for
more than a Sunday with ten, which is correct. The unweighted version treats
them as equals, and one quiet day can move the figure visibly.

This is also why a correct CTR chart and its headline do not match. Each
point is that day's own ratio; the headline is the period's. That is not a
bug and it is worth saying in any interface that shows both.

## Why a falling CTR is often good

The least intuitive thing about this metric, and the reason it is the most
misread number in search.

CTR falls when a page starts ranking for broader terms. More impressions at
worse positions means a smaller share convert, while the page earns **more
clicks in total**. The percentage fell and the outcome improved.

Three more things lower CTR with nothing going wrong:

- **Google answering the query on the results page.** Outside your control.
- **A rich result above you** taking the clicks that would have been yours.
- **Ranking for the first time on a new page**, which starts at zero and
  climbs.

## When a falling CTR is genuinely bad

When impressions and position are both steady and clicks fall. That isolates
the one variable you control: what your result says.

A page at position two with a low CTR is a snippet problem. The title or the
meta description is not answering the query somebody typed, and that is
directly fixable.

## Never read CTR alone

A rate with no volume beside it has no direction.

| CTR  | Impressions | What it means                         |
| ---- | ----------- | ------------------------------------- |
| Down | Up          | Ranking more broadly. Usually good    |
| Down | Flat        | Something changed in the result. Look |
| Up   | Down        | Smaller, better-matched audience      |
| Up   | Up          | The good one                          |

Place impressions and average position next to it, always.

## CTR outside search

The same ratio appears in email, ads and in-app prompts, and the same rules
apply. It is clicks over whatever was shown, and it is meaningless without
knowing how many were shown.

The one difference worth knowing is that search CTR is heavily determined by
position in a way email CTR is not. Half of the variation in a page's CTR is
explained by where it ranks, which makes comparing two pages' CTRs without
comparing their positions nearly worthless.

## CTR in Notch Metrics

[Search Console click-through rate](/sources/google-search-console/ctr) is
reported as a ratio over the window rather than the mean of daily rates.

Place it beside [clicks](/sources/google-search-console/clicks),
[impressions](/sources/google-search-console/impressions) and
[average position](/sources/google-search-console/average-position), because
those three together are the only way to read it.

[How to get average position and CTR from Search Console](/blog/get-average-position-and-ctr-from-search-console)
