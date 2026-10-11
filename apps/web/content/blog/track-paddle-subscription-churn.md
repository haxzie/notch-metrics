---
title: "How to track Paddle subscription churn"
description: "Paused is not churned and past due is not churned. How to count Paddle cancellations properly, and why the API makes it awkward."
date: 2026-10-11
author: Notch Metrics
tags: [paddle, churn, api]
pillar: paddle-mrr-on-your-mac
faq:
  - question: Does a paused Paddle subscription count as churn?
    answer: >-
      No. A pause is suspended on purpose and Paddle will resume billing.
      Counting it as churn makes a feature you deliberately offered look like a
      loss, and it double counts when the customer resumes.
  - question: Can the Paddle API filter subscriptions by cancellation date?
    answer: >-
      No. There is no canceled_at operator on the subscriptions endpoint, so
      counting cancellations in a window means paging the list and filtering
      client-side. For anything at scale, record the date yourself from the
      subscription.canceled webhook.
  - question: What is scheduled_change on a Paddle subscription?
    answer: >-
      It is where a pending cancellation lives before it takes effect. A
      subscription cancelled with the period left to run stays active with a
      scheduled change of type cancel and an effective_at date, which makes it a
      leading indicator of churn.
  - question: Does past_due count as Paddle churn?
    answer: >-
      No. A payment is failing and dunning is retrying it. Counting past due as
      churn means counting the same customer again when it finally cancels, and
      the figure moves whenever you change your retry schedule.
  - question: Why does my Paddle churn series shift when I change dunning settings?
    answer: >-
      Because involuntary churn only becomes a cancellation after your retry
      schedule gives up. A longer schedule pushes every involuntary cancellation
      later, with no change in customer behaviour at all.
---

## What counts as Paddle churn?

Only `canceled`. Paddle has five subscription statuses and three of them look
like churn without being it.

| Status     | Churn?                                          |
| ---------- | ----------------------------------------------- |
| `active`   | No                                              |
| `trialing` | No, and not revenue either                      |
| `paused`   | No. Suspended on purpose, billing will resume   |
| `past_due` | No. A payment is failing and dunning is running |
| `canceled` | Yes                                             |

`paused` is the one that catches people. A customer who pauses intends to
come back and Paddle will resume billing them. Counting a pause as churn
makes a feature you deliberately offered look like a loss, and it double
counts when they resume.

`past_due` is the other. Dunning runs for however long you configured, and
during that time the customer has not left. Counting past due as churn means
counting again when it finally cancels.

## The awkward part

Paddle's API cannot filter subscriptions by date. There is no
`canceled_at[GTE]`. To answer "how many subscriptions were cancelled last
week" you read the subscription list and filter client-side.

```js
async function churned(key, from, to) {
  let count = 0;
  let url = "https://api.paddle.com/subscriptions?status=canceled&per_page=100";

  while (url) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${key}` } });
    const body = await res.json();

    for (const sub of body.data) {
      const at = Date.parse(sub.canceled_at ?? "");
      if (at >= from && at < to) count += 1;
    }

    url = body.meta?.pagination?.next ?? null;
  }

  return count;
}
```

That works and it does not scale. An account with fifty thousand historical
cancellations pages through all of them to answer a question about seven
days, every time.

The fix is the same one it always is: subscribe to
`subscription.canceled` on a webhook, record the date in your own store, and
query that. Paddle's notification system is reliable and this is what it is
for.

## canceled_at against the period end

`canceled_at` is when the cancellation took effect. Paddle also carries
`scheduled_change`, which is where a pending cancellation lives before it
happens: a subscription cancelled with the period left to run is still
`active` with a scheduled change of type `cancel` and an `effective_at` date.

So there are two populations worth tracking separately. Subscriptions that
have ended, and subscriptions that are going to. The second is a leading
indicator and it is sitting in plain sight on the active list.

## Dunning makes churn lag

Involuntary churn arrives through `past_due` and only becomes `canceled`
after your retry schedule gives up. Change the schedule and the whole churn
series shifts, with no change in customer behaviour at all.

Worth remembering before reading a step in the chart as a product signal.

## Count, not rate

This counts subscriptions lost. A rate needs a denominator and there is no
agreed one: active at the start of the window, active plus new, or MRR rather
than count all produce different figures.

Pick one, write it down, and do not change it quietly.

## In the notch

Notch Metrics reports
[Paddle churned subscriptions](/sources/paddle/churned-subscribers) as a
count, bucketed by `canceled_at`, with a sparkline and a comparison against
the previous window. Paddle cannot filter by date, so the list is read and
bounded, which is stated on the page rather than hidden.

Place it beside
[new subscriptions](/sources/paddle/new-subscribers) and
[MRR](/sources/paddle/mrr).
[Everything Paddle reports](/sources/paddle), or
[download Notch Metrics](/download).
