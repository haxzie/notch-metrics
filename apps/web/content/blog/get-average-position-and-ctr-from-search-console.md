---
title: "How to get average position and CTR from Search Console"
description: "Both are ratios over the window, not averages of daily values. Why a falling CTR can be good news and what average position really describes."
date: 2026-10-11
author: Notch Metrics
tags: [google-search-console, seo, api]
pillar: search-console-clicks-in-your-notch
faq:
  - question: How is Search Console CTR calculated?
    answer: >-
      Clicks divided by impressions over whatever the row covers. For a window
      figure, ask with no dimensions and Google computes it across the whole
      range, weighting each day by its impressions.
  - question: Why does my CTR headline not match the average of the daily values?
    answer: >-
      Because the headline weights each day by its impressions and a naive
      average weights them equally. A Sunday with ten impressions should not
      count as much as a Monday with ten thousand, and a tool whose headline
      equals the mean of its points is doing the wrong calculation.
  - question: Is a falling Search Console CTR bad?
    answer: >-
      Often not. CTR falls when a page starts ranking for broader terms, so more
      impressions at worse positions convert at a lower rate while total clicks
      rise. It also falls when Google answers the query on the results page,
      which is outside your control.
  - question: What does Search Console average position mean?
    answer: >-
      The position of the topmost result for your site, averaged over every
      impression. It mixes unrelated queries, is weighted by impressions, and
      can move when nothing about your site changed, such as when you start
      ranking for new long-tail terms.
  - question: Which pages are worth optimising from Search Console?
    answer: >-
      Pages with high impressions sitting roughly between position five and
      fifteen. They are visible and not quite winning, so a title or description
      change has somewhere to move them. A page at position two with low CTR is
      usually a snippet problem instead.
---

## Both numbers are ratios, and that changes the arithmetic

Clicks and impressions are counts. CTR and position are not: they are
computed over whatever the row covers, and they cannot be added, averaged
across rows, or summed.

```json
{
  "startDate": "2026-10-01",
  "endDate": "2026-10-07",
  "dimensions": []
}
```

No dimensions, one row, and Google computes both correctly over the whole
window. That is the only figure you should quote as "our CTR".

## Why the headline does not match the chart

Ask for `dimensions: ["date"]` and each row holds that day's own ratio. The
windowed ratio is clicks over impressions across all seven days, which
weights each day by its impressions.

A Sunday with ten impressions and a Monday with ten thousand carry their real
weight in the headline and equal weight in a naive average of the points. The
difference can be large, and a tool whose headline equals the mean of its
points is doing the wrong calculation.

So the chart and the headline disagreeing is correct, and worth saying in the
interface before somebody files it as a bug.

## What average position actually describes

The position of the topmost result for your site, averaged over every
impression it received.

Three consequences.

**It mixes queries that have nothing to do with each other.** Ranking first
for a term nobody searches and fortieth for the term everyone does averages
to something in the middle, describing neither.

**It moves when nothing about you changed.** Start appearing fifth for ten
new long-tail queries and your average drops even though every existing
position held exactly.

**It is impression-weighted.** A position change on a high-volume query moves
it far more than the same change on a quiet one.

Treat a shift as a prompt to look at the query breakdown, not as a result.

## Why a falling CTR is often good

CTR falls when a page starts ranking for broader terms. More impressions at
worse positions means a smaller share of them convert, and the page is
earning more clicks in total while the percentage drops.

Three things that lower CTR without anything going wrong:

- Ranking for more, and therefore more loosely matched, queries.
- Google answering the query on the results page, which is outside your
  control.
- A rich result above you taking the clicks.

Always read CTR with impressions and position beside it. Alone it is the most
misinterpreted number Search Console publishes.

## The pair that is actually actionable

Page-level rows where impressions are high and position is between roughly
five and fifteen. Those pages are visible and not quite winning, and a title
or description change has somewhere to move them.

```json
{
  "startDate": "2026-09-01",
  "endDate": "2026-10-01",
  "dimensions": ["page"],
  "rowLimit": 500
}
```

Filter client-side on position and sort by impressions. A page at position
two with a low CTR is a different problem, usually a snippet one.

## The lag applies here too

Both ratios settle over two to three days along with their inputs. A CTR for
yesterday is computed from incomplete clicks and incomplete impressions, and
the two do not necessarily settle at the same rate.

End your window three days back for anything you intend to compare.

## In the notch

Notch Metrics reports
[Search Console CTR](/sources/google-search-console/ctr) as clicks divided by
impressions over the window, rather than the mean of daily rates, and
[average position](/sources/google-search-console/average-position) with one
decimal place and a note that lower is better.

Both say on their pages how they are computed, because a ratio whose
definition is hidden is a ratio somebody will misread.
[Everything Search Console reports](/sources/google-search-console), or
[download Notch Metrics](/download).
