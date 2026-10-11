---
title: "How to count active Lemon Squeezy subscriptions"
description: "Seven statuses, and only some of them are customers. What active means in Lemon Squeezy, and why trials make the obvious count ambiguous."
date: 2026-10-11
author: Notch Metrics
tags: [lemonsqueezy, subscribers, api]
pillar: lemon-squeezy-mrr-on-your-mac
faq:
  - question: How many statuses does a Lemon Squeezy subscription have?
    answer: >-
      Seven: on_trial, active, paused, past_due, unpaid, cancelled and expired.
      Which ones you count depends on whether you are asking who is paying, who
      has access, or how big the committed book is.
  - question: Does Lemon Squeezy count trials as active subscribers?
    answer: >-
      Yes, in its own dashboard figure. Filtering the API on
      filter[status]=active excludes trials and therefore returns fewer rows
      than the dashboard shows. Neither is wrong, they answer different
      questions.
  - question: Is a cancelled Lemon Squeezy subscription still paying?
    answer: >-
      Until ends_at, yes. Somebody who cancels an annual plan today is cancelled
      and paid up for another eleven months. The count of cancelled
      subscriptions with a future ends_at is revenue you are going to lose,
      visible months ahead.
  - question: What does past_due mean in Lemon Squeezy?
    answer: >-
      A payment failed and dunning is retrying. Most recover, so counting
      past_due as churn means counting the loss twice, once now and once when
      the subscription actually goes unpaid. Track it separately as the churn
      you can fix.
  - question: Why do my Lemon Squeezy subscriber count and MRR disagree?
    answer: >-
      Because the active subscriber figure includes trials and MRR does not. The
      gap between the two is how many people are still deciding.
---

## What counts as an active Lemon Squeezy subscription?

It depends what you are counting for, and Lemon Squeezy's own answer is not
the only reasonable one.

A subscription has one of seven statuses.

| Status      | Paying now?         | Has access?           |
| ----------- | ------------------- | --------------------- |
| `on_trial`  | No                  | Yes                   |
| `active`    | Yes                 | Yes                   |
| `paused`    | No                  | Depends on your setup |
| `past_due`  | Payment failing     | Usually yes           |
| `unpaid`    | No, dunning gave up | Usually no            |
| `cancelled` | Until `ends_at`     | Until `ends_at`       |
| `expired`   | No                  | No                    |

Three different questions produce three different counts.

**How many people are paying me?** `active` alone.

**How many people have access?** `active`, `on_trial`, `past_due`, and
`cancelled` that has not reached `ends_at`. This is the number your
infrastructure costs track.

**How big is the book?** `active` plus `cancelled` before `ends_at`, because
that money is already committed.

None of these is wrong. Picking one quietly and calling it "subscribers" is.

## The call

```bash
curl -s 'https://api.lemonsqueezy.com/v1/subscriptions?filter[store_id]=12345&filter[status]=active&page[size]=100' \
  -H 'Accept: application/vnd.api+json' \
  -H 'Authorization: Bearer <api key>'
```

Remember this is JSON:API: the status is at `data[].attributes.status`, not
`data[].status`.

## Lemon Squeezy's own count includes trials

Worth knowing before you compare your figure against the dashboard. Lemon
Squeezy reports trialling subscriptions as active in its own subscriber
count, so a filter on `filter[status]=active` returns fewer rows than the
dashboard shows.

Neither is a bug. They are answering the second question and the first
question respectively.

## cancelled is not expired

The distinction people miss. A `cancelled` subscription keeps running until
`ends_at`. Somebody who cancels an annual plan today is `cancelled` and
paying for another eleven months.

```js
const stillRunning = subs.filter((s) => {
  const a = s.attributes;
  if (a.status === "active" || a.status === "on_trial") return true;
  if (a.status === "cancelled") return Date.parse(a.ends_at) > Date.now();
  return false;
});
```

That is also where your churn leading indicator lives. The count of
`cancelled` subscriptions with a future `ends_at` is revenue you are going to
lose, visible months before it goes.

## past_due is recoverable

A `past_due` subscription is a card that failed and dunning retrying. Most
recover. Counting them as lost today means counting the loss twice: once now
and once when they actually go `unpaid`.

Watch the `past_due` count as its own number. It is the churn you can fix.

## In the notch

Notch Metrics reports
[Lemon Squeezy active subscribers](/sources/lemonsqueezy/active-subscribers)
as subscriptions in status `active` right now, trials included, which is
Lemon Squeezy's own definition. The page says so rather than leaving you to
discover it from a disagreement with the dashboard.

Place it beside [MRR](/sources/lemonsqueezy/mrr), which excludes trials, and
the gap between the two is how many people are still deciding.

[Everything Lemon Squeezy reports](/sources/lemonsqueezy), or
[download Notch Metrics](/download).
