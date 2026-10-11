---
title: "How to calculate MRR from the Polar API"
description: "Polar has an MRR endpoint, which puts it ahead of most. Here is how to call it, what it counts, and when to compute your own instead."
date: 2026-10-11
author: Notch Metrics
tags: [polar, mrr, api]
pillar: polar-revenue-in-your-notch
faq:
  - question: Does the Polar API have an MRR endpoint?
    answer: >-
      Yes. GET /v1/metrics/ with metrics=monthly_recurring_revenue returns
      Polar's own MRR per interval. That is unusual among payment providers,
      most of which make you derive MRR from a subscriptions list.
  - question: How does Polar define MRR?
    answer: >-
      Active subscriptions normalised to a month, with yearly plans divided by
      twelve and trials excluded. It is the same definition the Polar dashboard
      shows, so an API figure and a dashboard figure agree.
  - question: Why does the Polar metrics endpoint return null for today?
    answer: >-
      Polar computes metrics on a pipeline and the newest period can be null
      until it catches up. Read the last period that has a value rather than the
      last period, or your figure reads zero shortly after midnight.
  - question: Which timezone does the Polar metrics endpoint use?
    answer: >-
      Whatever you pass in the timezone parameter, and Polar's default if you
      pass nothing. Pass an IANA name such as Europe/London rather than an
      offset so daylight saving is handled.
  - question: What is the Polar sandbox API URL?
    answer: >-
      sandbox-api.polar.sh, against production's api.polar.sh. A token from one
      used against the other returns 401, which looks like a bad token rather
      than a wrong host.
---

## Does Polar have an MRR endpoint?

Yes, and that is unusual. Most payment providers make you derive MRR from a
subscriptions list and argue with yourself about the definition. Polar
computes it server-side and serves it from `/v1/metrics/`.

```bash
curl -s 'https://api.polar.sh/v1/metrics/?start_date=2026-09-01&end_date=2026-10-01&interval=day&metrics=monthly_recurring_revenue' \
  -H 'Authorization: Bearer polar_oat_...'
```

The response carries a `periods` array, one entry per interval, each holding
the metric values you asked for.

## What Polar's MRR counts

Active subscriptions, normalised to a month. Yearly plans are divided by
twelve. Trials are excluded. That is a reasonable definition and, more
usefully, it is the same definition the Polar dashboard shows, so your number
and the one your co-founder is looking at will match.

Ask for `metrics=monthly_recurring_revenue` explicitly. The endpoint will
compute fifty-odd figures per call if you let it, and asking for one is
faster and kinder.

## The trap: null periods

Polar computes metrics on a pipeline, and the newest period can come back
with `null` for a while before it is filled in. Code that reads
`periods.at(-1)` will show zero shortly after midnight and then correct
itself.

```js
function latestMrr(periods) {
  // The last period with a value, not the last period. A null newest
  // bucket is a pipeline that has not caught up, not an MRR of zero.
  return (
    [...periods].reverse().find((p) => typeof p.monthly_recurring_revenue === "number")
      ?.monthly_recurring_revenue ?? null
  );
}
```

Ask for a week of daily periods rather than one, so there is something to
fall back to.

## Timezone

`/v1/metrics/` takes a `timezone` parameter and it is worth passing
explicitly. Omit it and your daily buckets follow Polar's default rather than
yours, and every figure near midnight lands on the day you did not expect.

Use an IANA name, `Europe/London` rather than an offset, so daylight saving
is handled for you.

## Sandbox and production are different hosts

Polar's sandbox lives at `sandbox-api.polar.sh` and production at
`api.polar.sh`. A production token against the sandbox host, or the reverse,
returns 401. That is better than returning an empty account, which is what
several providers do, but it still looks like a bad token rather than a wrong
host.

## When to compute your own instead

Polar's figure is the right default. Compute your own if you need a
definition Polar does not offer: MRR excluding a particular product, MRR by
plan tier, or a figure that nets off a discount Polar counts differently.

In that case list subscriptions and normalise each one yourself, the same way
you would on any provider. Be aware that you are now maintaining a number
that will drift from the dashboard, and that somebody will eventually ask
which is right.

## Or put Polar's own figure in the notch

Notch Metrics reads [Polar MRR](/sources/polar/mrr) from that endpoint,
handles the null periods, and shows it in the MacBook notch. It also reports
[revenue](/sources/polar/revenue),
[active](/sources/polar/active-subscribers),
[new](/sources/polar/new-subscribers) and
[churned subscriptions](/sources/polar/churned-subscribers), and a feed of
[recent orders](/sources/polar/recent-payments).

Connect once on the web, and the token never reaches your Mac.
[Download Notch Metrics](/download).
