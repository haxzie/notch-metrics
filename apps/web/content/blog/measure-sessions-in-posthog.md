---
title: "How to measure sessions in PostHog"
description: "Sessions are derived, not recorded. How PostHog stitches them, when one ends, and why session counts move when nothing else did."
date: 2026-10-11
author: Notch Metrics
tags: [posthog, sessions, api]
pillar: posthog-active-users-on-your-mac
faq:
  - question: What is a session in PostHog?
    answer: >-
      A run of activity from one person with no gap longer than thirty minutes.
      PostHog derives sessions from the event stream rather than recording them,
      which is why session numbers behave differently from users and pageviews.
  - question: How do I count sessions in PostHog with HogQL?
    answer: >-
      SELECT count() FROM the sessions table, bucketing on min_timestamp so a
      session that spans midnight is counted on the day it started.
  - question: Why did my PostHog session count drop suddenly?
    answer: >-
      Often a background poll. If your app sends events on a timer, sessions
      never reach the thirty-minute gap that ends them, so many visits merge
      into one long session. Adding heartbeat tracking is the usual cause.
  - question: Are sessions the same as visits or users?
    answer: >-
      No. One person can produce many sessions in a day and many pageviews in a
      session. Sessions count runs of activity split on a thirty-minute gap,
      users are de-duplicated people, and pageviews count every load.
  - question: What is the most useful thing to do with a session count?
    answer: >-
      Divide pageviews by it. Depth rising means people are reading more. Depth
      rising while sessions fall is usually a navigation problem, with the same
      people hunting for something that used to be easy to find.
---

## What is a PostHog session?

A run of activity from one person with no gap longer than thirty minutes.
PostHog does not record sessions; it derives them from the event stream, and
everything odd about session numbers follows from that.

## The query

PostHog exposes a `sessions` table in HogQL, which saves you stitching events
yourself.

```sql
SELECT toUnixTimestamp(toStartOfDay(min_timestamp)) AS bucket, count() AS value
FROM sessions
WHERE min_timestamp >= toDateTime({from}) AND min_timestamp < toDateTime({to})
GROUP BY bucket
ORDER BY bucket
```

`min_timestamp` is when the session started, and bucketing on it means a
session that spans midnight is counted on the day it began. That is the
convention every analytics tool uses and it is worth knowing you are
accepting it.

## The thirty-minute rule, and what it does to your numbers

Somebody reading a long article, going to make tea, and coming back after
thirty-five minutes is two sessions. Somebody who leaves a tab open in the
background and clicks once an hour is many sessions.

Neither is a bug. It is the definition doing its job, and it means session
counts are sensitive to how your product is used in a way that pageviews and
users are not. A product people keep open in a tab all day produces session
counts that have very little to do with how many times they decided to use
it.

## Sessions move when nothing moved

Three things change session counts without any change in traffic.

**A background poll.** If your app sends an event on a timer, sessions never
end and your session count collapses. People discover this after adding
heartbeat tracking.

**A tracking change.** Firing more events in the gaps bridges what would have
been two sessions into one.

**Identity merging.** When PostHog merges two persons, their sessions merge
too, which can change historical figures.

So a session series is the least stable of the standard metrics, and reading
a step in it as a behaviour change is usually wrong.

## Pageviews per session is the useful form

Sessions on their own say little. Divided into pageviews they say how deep a
visit goes.

```sql
-- Two queries, divided client-side. Keep the window identical.
SELECT count() FROM events WHERE event = '$pageview' AND ...
SELECT count() FROM sessions WHERE ...
```

Depth rising is people reading more. Depth rising while sessions fall is
usually a navigation problem, with the same people hunting for something that
used to be easy to find.

## Sessions are not visits, and not users

Three different numbers that get used interchangeably in conversation and
should never be in a chart.

|           | What it counts                                 |
| --------- | ---------------------------------------------- |
| Sessions  | Runs of activity, split on a thirty-minute gap |
| Users     | De-duplicated people over the window           |
| Pageviews | Every page load, repeats included              |

One person can produce many sessions in a day and many pageviews in a
session. Label the axis.

## Or read it off the notch

Notch Metrics reports [PostHog sessions](/sources/posthog/sessions) as
sessions started in the window, bucketed hourly, daily, weekly or monthly in
your PostHog project's own timezone, with a sparkline and a comparison
against the previous window.

Place it beside [pageviews](/sources/posthog/pageviews) and
[active users](/sources/posthog/active-users) and the three describe the
visit rather than just counting it.
[Everything PostHog reports](/sources/posthog), or
[download Notch Metrics](/download).
