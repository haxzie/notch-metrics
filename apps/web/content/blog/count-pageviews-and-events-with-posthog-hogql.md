---
title: "How to count pageviews and events with PostHog HogQL"
description: "Counting events is easy. Knowing what you counted is not, because autocapture puts a lot of things in the same table."
date: 2026-10-11
author: Notch Metrics
tags: [posthog, events, api]
pillar: posthog-active-users-on-your-mac
faq:
  - question: How do I count events in PostHog with HogQL?
    answer: >-
      SELECT count() FROM events with a bounded timestamp range, grouped by
      toStartOfDay for a series. Always bound the timestamp first: an unbounded
      scan over a busy project is slow enough to time out.
  - question: Does PostHog autocapture inflate my event count?
    answer: >-
      Yes, usually by several times. Autocapture records a $autocapture event
      for most clicks and form interactions, on top of $pageview, $pageleave and
      your own events. Filter with NOT startsWith(event, '$') for your own
      instrumentation only.
  - question: How do I count pageviews in PostHog?
    answer: >-
      Filter on event = '$pageview' and use count(), not uniq(). Repeat views by
      one person all count, which is what a pageview is.
  - question: Why is my PostHog pageview count wrong in a single-page app?
    answer: >-
      Because it reflects whatever your router was wired to send. Some apps fire
      one $pageview per route change, some per modal, and some none after the
      first load. If the figure is an order of magnitude off, check the
      instrumentation before the traffic.
  - question: Why does my filtered PostHog query return zero?
    answer: >-
      Often a typo in a property name. Properties are a JSON column and a
      missing one returns null rather than erroring, so a filter on it silently
      matches nothing. Sanity check against a known unfiltered total.
---

## The query

```sql
SELECT toUnixTimestamp(toStartOfDay(timestamp)) AS bucket, count() AS value
FROM events
WHERE timestamp >= toDateTime({from}) AND timestamp < toDateTime({to})
GROUP BY bucket
ORDER BY bucket
```

That is every event. The interesting question is whether that is what you
meant.

## Autocapture is probably most of your volume

If autocapture is enabled, PostHog records a `$autocapture` event for most
clicks and form interactions on the page, plus `$pageview` and `$pageleave`
on top of your own named events.

A product with autocapture on produces several times the volume its own
instrumentation would suggest. That makes a raw event count:

- **A good billing signal.** PostHog meters on events ingested, so this
  number is roughly next month's invoice.
- **A weak product signal.** One noisy component can double it with nobody
  new arriving.

Filter if you want a product number:

```sql
-- Your own events only.
WHERE NOT startsWith(event, '$')
```

PostHog prefixes its own events with `$`, so that one clause separates your
instrumentation from the framework's opinion of what a click is.

## Pageviews

```sql
SELECT toUnixTimestamp(toStartOfDay(timestamp)) AS bucket, count() AS value
FROM events
WHERE event = '$pageview'
  AND timestamp >= toDateTime({from}) AND timestamp < toDateTime({to})
GROUP BY bucket ORDER BY bucket
```

`count()` here, not `uniq()`. Repeat views by one person all count, which is
what a pageview is.

## The single-page-app caveat

On a server-rendered site the snippet fires one `$pageview` per navigation
and the number means what you expect.

In a single-page application it means whatever your router was wired to send.
Some apps fire one per route change. Some fire one per modal. Some fire none
after the first load, because the integration was finished enough to ship and
never revisited.

If your pageview count is an order of magnitude away from your server logs,
check the instrumentation before you check the traffic.

## Counting a specific event

```sql
WHERE event = 'subscription_created'
```

And for a property:

```sql
WHERE event = 'subscription_created'
  AND properties.plan = 'annual'
```

Properties are a JSON column, accessed with dot notation. A property that
does not exist returns null rather than erroring, so a typo in a property
name silently returns zero. That is worth a sanity check against a known
total before you trust any filtered figure.

## Performance

`events` is large. Two things keep a query fast.

**Always bound the timestamp.** An unbounded scan over a busy project is slow
enough to time out, and the first clause of every `WHERE` should be the
window.

**Filter on `event` before properties.** `event` is indexed in a way that
properties are not, so narrowing by event name first makes a property filter
cheap instead of catastrophic.

## Or read it off the notch

Notch Metrics reports [PostHog events](/sources/posthog/events) as everything
ingested in the window and
[pageviews](/sources/posthog/pageviews) as `$pageview` events, both bucketed
hourly, daily, weekly or monthly with a sparkline and a comparison against
the previous window.

Put [active users](/sources/posthog/active-users) beside events, and events
climbing while active users hold flat means you shipped more tracking rather
than more usage. [Everything PostHog reports](/sources/posthog), or
[download Notch Metrics](/download).
