---
title: "How to get realtime visitors from Plausible"
description: "One endpoint, one integer, and a five-minute window that is not what most people assume. How Plausible counts who is on your site now."
date: 2026-10-11
author: Notch Metrics
tags: [plausible, realtime, api]
pillar: plausible-visitors-in-your-notch
faq:
  - question: What is the Plausible realtime visitors endpoint?
    answer: >-
      GET /api/v1/stats/realtime/visitors with a site_id parameter and a bearer
      token. It returns a bare integer rather than a JSON object, so code
      expecting an object reads undefined and reports zero forever.
  - question: How long is the Plausible realtime window?
    answer: >-
      Five minutes. A realtime visitor is somebody who sent an event in the last
      five minutes, not somebody with a tab open. A reader who has been still
      for five minutes is on your site and not in the number.
  - question: Is there a v2 version of the Plausible realtime endpoint?
    answer: >-
      No, and that is deliberate. Realtime is a single scalar with no
      dimensions, metrics list or date range, so it stayed on v1 where a query
      object would be ceremony around one number.
  - question: How often should I poll Plausible realtime visitors?
    answer: >-
      Thirty to sixty seconds. Faster buys nothing a human can read and
      Plausible's rate limits are sized for dashboards rather than tight loops.
  - question: Why does my Plausible realtime count keep showing zero?
    answer: >-
      Either the site is genuinely quiet in a five-minute window, which is
      normal on a small site, or a failed request is being read as zero. Return
      null on failure instead, because a failed call that reports zero looks
      exactly like a quiet night.
---

## The endpoint

```bash
curl -s 'https://plausible.io/api/v1/stats/realtime/visitors?site_id=example.com' \
  -H 'Authorization: Bearer <api key>'
```

The response is `47`. Not `{"visitors": 47}`, just the integer. Any JSON
parser handles it, but code expecting an object gets `undefined` and reports
zero visitors forever.

## It is still v1, deliberately

Plausible moved its querying to a v2 POST endpoint, and realtime stayed
behind on v1. That is not an oversight: realtime is a single scalar with no
dimensions, no metrics list and no date range, so a query object would be
ceremony around one number.

Do not go looking for a v2 equivalent. This is the endpoint.

## The window is five minutes

A realtime visitor is somebody who sent an event in the last five minutes.
Not somebody with a tab open, and not somebody currently reading.

Two consequences.

**Somebody reading a long article is not counted** once they have been still
for five minutes, unless your setup sends engagement events. They are on your
site and they are not in the number.

**The figure is lumpy on a small site.** One person arriving and leaving
moves it by a whole unit, so a site with twenty visitors a day shows mostly
zero punctuated by ones. That is not a broken integration.

## What to use it for

Not trends. A five-minute scalar has no history, and polling it to build one
gives you a sampled series with gaps wherever your poll missed.

What it is good for is the moment. You post a launch, you share a link, you
go on a podcast, and the number tells you whether anything is happening right
now. That is a genuinely different question from "how was this week", and it
is the one worth putting somewhere you can see without typing.

## Polling politely

The figure changes constantly and the API is not a stream. Something in the
range of thirty to sixty seconds is plenty: faster buys you nothing a human
can read, and Plausible's rate limits are sized for dashboards rather than
for tight loops.

```js
async function current(siteId, key) {
  const res = await fetch(
    `https://plausible.io/api/v1/stats/realtime/visitors?site_id=${encodeURIComponent(siteId)}`,
    { headers: { Authorization: `Bearer ${key}` } },
  );
  if (!res.ok) return null; // Null, not zero. They are different.
  return Number(await res.text());
}
```

Returning `null` on failure rather than `0` matters more than it looks. A
failed call that reports zero visitors looks exactly like a quiet night, and
you will believe it.

## Self-hosted

The same path works on a self-hosted instance, with your own host in place of
`plausible.io`. The hosted connector in Notch Metrics targets Plausible
Cloud; for a self-hosted box, a
[custom metric](/blog/writing-a-custom-metric) declaring your own host is the
route.

## In the notch

Notch Metrics reports
[Plausible unique visitors](/sources/plausible/visitors) and
[pageviews](/sources/plausible/pageviews) in the MacBook notch over whatever
window you choose, bucketed in the site's own timezone.

For the launch-day question, place a short window and hover the camera
housing. [Everything Plausible reports](/sources/plausible), or
[download Notch Metrics](/download).
