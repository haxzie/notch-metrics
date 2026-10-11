---
title: "How to count events in Amplitude by API"
description: "The segmentation endpoint, the event filter JSON that must be URL encoded, and why event volume is a billing signal more than a product one."
date: 2026-10-11
author: Notch Metrics
tags: [amplitude, events, api]
pillar: amplitude-active-users-on-your-mac
faq:
  - question: Which Amplitude endpoint returns event counts?
    answer: >-
      /api/2/events/segmentation, with an e parameter holding a URL-encoded JSON
      object. The users endpoint answers active and new users and does not count
      events.
  - question: What does event_type _active mean in Amplitude?
    answer: >-
      Any event, of any type. It is one of two reserved types, alongside _new,
      which matches a user's first event. For a specific event, pass its name
      instead.
  - question: Why does my Amplitude segmentation call return a 400?
    answer: >-
      Usually the e parameter is not URL encoded. It is JSON inside a query
      string, so braces and quotes must be escaped. Use URLSearchParams rather
      than building the string by hand.
  - question: What is the difference between totals and uniques in Amplitude?
    answer: >-
      totals counts every event with repeats included. uniques counts distinct
      users who fired it. People often reach for totals to answer how many
      people did something, which uniques is the right metric for.
  - question: Is Amplitude event volume a good product metric?
    answer: >-
      It is a better billing signal than a product one, because Amplitude meters
      on event volume. A component that starts firing twice doubles the number
      with nobody new arriving, so place active users beside it.
---

## The endpoint

Event counts come from `/api/2/events/segmentation`, not from the users
endpoint.

```bash
curl -s -u "$API_KEY:$SECRET_KEY" \
  'https://amplitude.com/api/2/events/segmentation?e=%7B%22event_type%22%3A%22_active%22%7D&start=20261001&end=20261007&i=1&m=totals'
```

That `e` parameter is a JSON object, URL encoded. Decoded it is:

```json
{ "event_type": "_active" }
```

## The special event types

Amplitude reserves two event types that are not events you sent.

| `event_type` | What it means          |
| ------------ | ---------------------- |
| `_active`    | Any event, of any type |
| `_new`       | A user's first event   |

`_active` is what you want for total volume. For one specific event, use its
name:

```json
{ "event_type": "subscription_created" }
```

## Encoding the e parameter

This is where most of the pain is. `e` is JSON in a query string, so it must
be encoded, and an unencoded brace will either 400 or silently mangle.

```js
const url = new URL("https://amplitude.com/api/2/events/segmentation");
url.searchParams.set("e", JSON.stringify({ event_type: "_active" }));
url.searchParams.set("start", "20261001");
url.searchParams.set("end", "20261007");
url.searchParams.set("i", "1");
url.searchParams.set("m", "totals");
```

`URLSearchParams` encodes for you. Building the string by hand is how the
quotes get lost.

## m decides totals against uniques

| `m`       | What you get                 |
| --------- | ---------------------------- |
| `totals`  | Every event, repeats counted |
| `uniques` | Distinct users who fired it  |
| `avg`     | Average per active user      |

`totals` for volume. `uniques` for "how many people did this", which is a
different and usually more useful question, and the one people reach for
`totals` by mistake to answer.

## Filtering on a property

```json
{
  "event_type": "subscription_created",
  "filters": [
    {
      "subprop_type": "event",
      "subprop_key": "plan",
      "subprop_op": "is",
      "subprop_value": ["annual"]
    }
  ]
}
```

`subprop_value` is an array even for one value. A string there is a quiet
no-match rather than an error, so a filtered figure that returns zero is
worth checking against the unfiltered one before you believe it.

## What a raw event count is good for

Amplitude bills on event volume, so this number is close to a live view of
next month's invoice. That is the use case where it is unambiguous.

As a product signal it is weak. A single component that starts firing twice
doubles your volume with nobody new arriving, and a tracking change looks
identical to a usage change in this series.

Put [active users](/sources/amplitude/active-users) beside it. Events
climbing while active users hold flat means you shipped more instrumentation.
Both climbing together means something actually happened.

## No autocapture, which helps

Unlike some product analytics tools, Amplitude does not autocapture by
default. Every event in that total is one your instrumentation deliberately
sent.

That makes the figure a cleaner product signal than an autocaptured one, and
a less useful proxy for user activity, because anything you forgot to
instrument is invisible rather than approximated.

## In the notch

Notch Metrics reports [Amplitude events](/sources/amplitude/events) as every
event recorded in the window, of every type, bucketed daily, weekly or
monthly in your project's own timezone, with a sparkline and a comparison
against the previous window.

[Everything Amplitude reports](/sources/amplitude), or
[download Notch Metrics](/download).
