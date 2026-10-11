---
title: "How to read bounce rate from Plausible"
description: "A bounce is a session with one pageview, which means a time-on-page problem. What Plausible's number includes and when it misleads."
date: 2026-10-11
author: Notch Metrics
tags: [plausible, bounce-rate, api]
pillar: plausible-visitors-in-your-notch
faq:
  - question: What counts as a bounce in Plausible?
    answer: >-
      A session with exactly one pageview. The visitor arrived, looked, and left
      without loading a second page. Time on the page is not part of the
      definition.
  - question: Is a high bounce rate bad?
    answer: >-
      Not necessarily. On a blog, a documentation page or a pricing page,
      somebody arriving, getting what they came for and leaving is the page
      working. It is genuinely bad only on a page whose job is to move somebody
      to a next step.
  - question: Why is my bounce rate nearly 100% in a single-page app?
    answer: >-
      Because your router is probably not firing a pageview on navigation, so
      every session has exactly one pageview. That is an instrumentation reading
      rather than a traffic reading.
  - question: Do anchor links reduce bounce rate in Plausible?
    answer: >-
      No. A same-page anchor is not a pageview, so an in-page table of contents
      does not affect the figure. That is correct behaviour and it catches
      people who expected otherwise.
  - question: Should I look at bounce rate on its own?
    answer: >-
      No. A rate has no direction without volume beside it. Bounce rate falling
      while visitors fall is a smaller, more committed audience rather than an
      improvement.
---

## What is a bounce in Plausible?

A session with exactly one pageview. The visitor arrived, looked, and left
without loading a second page.

```bash
curl -s https://plausible.io/api/v2/query \
  -H 'Authorization: Bearer <api key>' \
  -H 'Content-Type: application/json' \
  -d '{
    "site_id": "example.com",
    "metrics": ["bounce_rate"],
    "date_range": "30d"
  }'
```

Plausible returns it as a percentage. Notch Metrics holds it as a fraction
and renders the percentage, because a ratio stored as a number between 0 and
100 is a number somebody eventually divides by 100 twice.

## The thing a bounce rate cannot see

Time. A session with one pageview is a bounce whether the visitor left after
two seconds or read for twenty minutes.

That is not a Plausible limitation, it is what a pageview-based definition
can know. Without a second page load or an engagement event, the browser
never tells anybody how long the visitor stayed.

So the number conflates two opposite outcomes: somebody who bounced off a
page that was wrong for them, and somebody who got exactly what they came for
on the first page and had no reason to click further.

## Which is why high is not automatically bad

Three cases where a high bounce rate is fine or good.

**A blog.** Search brings somebody to one article, they read it, they leave.
That is the article working.

**A documentation page.** They came for a specific answer, found it, and went
back to their editor. A low bounce rate here would mean people cannot find
things.

**A contact or pricing page as a landing page.** One page, one decision.

The case where it is genuinely bad is a landing page whose whole job is to
move somebody to the next step. There a bounce is a failure, and the number
is directly actionable.

Segment before you judge. A site-wide bounce rate averages a blog that should
bounce with a funnel that should not, and the average describes neither.

```json
{
  "site_id": "example.com",
  "metrics": ["bounce_rate", "visitors"],
  "date_range": "30d",
  "dimensions": ["event:page"]
}
```

## Where the number moves without behaviour changing

**Adding a cookie banner that fires an event.** If a consent interaction
registers as activity, bounces fall overnight with nobody reading more.

**Anchor links.** A same-page anchor is not a pageview in Plausible, so an
in-page table of contents does not rescue a bounce rate, which is correct and
catches people who expected it to.

**Single-page apps.** If your router does not fire a pageview on navigation,
every session is one pageview and your bounce rate is near 100%. That is an
instrumentation reading, not a traffic reading, and it is the first thing to
check if the figure looks absurd.

## Read it with visitors

A bounce rate falling while visitors fall is not an improvement, it is a
smaller and more committed audience. Falling while visitors rise is the
genuinely good case.

The ratio alone has no direction. Put the volume beside it.

## In the notch

Notch Metrics reports
[Plausible bounce rate](/sources/plausible/bounce-rate) as a ratio, bucketed
daily, weekly or monthly in your Plausible site's own timezone, with a
sparkline and a comparison against the previous window.

Place it beside [unique visitors](/sources/plausible/visitors) and
[pageviews](/sources/plausible/pageviews), because a rate with no volume next
to it is a number you cannot act on.
[Everything Plausible reports](/sources/plausible), or
[download Notch Metrics](/download).
