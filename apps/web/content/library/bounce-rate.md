---
title: "What is bounce rate?"
description: "A bounce is a single-page visit, which means bounce rate cannot see time. Why high is often fine, and why GA4's definition is different."
date: 2026-10-11
author: Notch Metrics
tags: [bounce-rate, analytics, glossary]
kind: glossary
term: Bounce rate
faq:
  - question: What counts as a bounce?
    answer: >-
      In most analytics tools, a session with exactly one page view: the visitor
      arrived and left without loading a second page. Time on the page is not
      part of the definition, so a two-second visit and a twenty-minute read are
      both bounces.
  - question: Is a high bounce rate bad?
    answer: >-
      Not necessarily. On a blog post, a documentation page or a pricing page,
      somebody arriving, getting what they came for and leaving is the page
      working. It is genuinely bad only on a page whose job is to move somebody
      onwards.
  - question: Is GA4 bounce rate the same as Universal Analytics bounce rate?
    answer: >-
      No. GA4 bounce rate is one minus engagement rate, where an engaged session
      lasted ten seconds or more, had two or more page views, or included a
      conversion. Universal Analytics counted single-page-view sessions. The two
      should never share an axis.
  - question: Why is my bounce rate nearly 100%?
    answer: >-
      Usually a single-page app whose router does not fire a page view on
      navigation, so every session has exactly one. That is an instrumentation
      reading rather than a traffic reading.
  - question: Do anchor links reduce bounce rate?
    answer: >-
      No. A same-page anchor is not a page view, so a table of contents does not
      affect the figure.
---

**Bounce rate is the share of sessions that contained exactly one page
view.** The visitor arrived, looked, and left without loading a second page.

## The thing it cannot see

Time. A session with one page view is a bounce whether the visitor left after
two seconds or read for twenty minutes.

That is not a limitation of any particular tool, it is what a page-view-based
definition can know. Without a second page load or an engagement event, the
browser never reports how long somebody stayed.

So the metric conflates two opposite outcomes: somebody who bounced off a
page that was wrong for them, and somebody who got exactly what they came for
on the first page and had no reason to click.

## Which is why high is often fine

Three cases where a high bounce rate is the page working.

**A blog post.** Search brings somebody to one article, they read it, they
leave. That is the article doing its job.

**A documentation page.** They came for a specific answer, found it, went
back to their editor. A low bounce rate here would mean people cannot find
things.

**A contact or pricing page as a landing page.** One page, one decision.

The case where it is genuinely bad is a page whose whole job is to move
somebody onwards. There a bounce is a failure, and the number is actionable.

Segment before you judge. A site-wide bounce rate averages a blog that should
bounce with a funnel that should not, and the average describes neither.

## GA4 changed the definition

Worth knowing if you are comparing across a migration.

Universal Analytics bounce rate was the single-page-view definition above.
GA4 bounce rate is **one minus engagement rate**, where an engaged session
lasted at least ten seconds, had two or more page views, or included a
conversion.

So a GA4 bounce is a session that did none of those. The two numbers are not
comparable and should never share an axis across the migration date.

GA4's is arguably the better definition, because the ten-second rule gives it
a crude view of the time the old one could not see.

## Where the number moves without behaviour changing

**A cookie banner that fires an event.** If a consent interaction registers
as activity, bounces fall overnight with nobody reading more.

**Anchor links.** A same-page anchor is not a page view, so a table of
contents does not rescue a bounce rate. Correct behaviour, and it catches
people who expected otherwise.

**A single-page app with no route tracking.** If your router does not fire a
page view on navigation, every session has exactly one and your bounce rate
is near 100%. That is an instrumentation reading, not a traffic reading, and
it is the first thing to check when the figure looks absurd.

## Read it with volume

Bounce rate falling while visitors fall is not an improvement, it is a
smaller and more committed audience. Falling while visitors rise is the
genuinely good case.

## Bounce rate in Notch Metrics

[Plausible bounce rate](/sources/plausible/bounce-rate) uses the
single-page-view definition and is reported as a ratio, bucketed in your
Plausible site's own timezone.

Place it beside [unique visitors](/sources/plausible/visitors) and
[pageviews](/sources/plausible/pageviews).

[How to read bounce rate from Plausible](/blog/read-bounce-rate-from-plausible)
