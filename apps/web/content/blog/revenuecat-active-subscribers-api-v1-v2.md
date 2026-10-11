---
title: "How to get active subscribers from the RevenueCat API, v1 against v2"
description: "There is no list-active-subscribers endpoint. What v1 and v2 actually offer, and which one answers the question you are asking."
date: 2026-10-11
author: Notch Metrics
tags: [revenuecat, subscribers, api]
pillar: revenuecat-mrr-and-trials-on-your-mac
faq:
  - question: Is there a RevenueCat API endpoint to list all active subscribers?
    answer: >-
      No. No endpoint returns every currently active subscriber as a list. The
      v2 project metrics overview returns the count, and for a list you have to
      maintain your own table from RevenueCat webhooks.
  - question: What is the difference between RevenueCat API v1 and v2?
    answer: >-
      v1 is oriented around looking up one customer by app user id, which is
      what you want inside an app. v2 adds project-scoped list and metrics
      endpoints. They use different keys: a v1 key against a v2 endpoint returns
      401, which reads like a revoked key rather than a wrong version.
  - question: Which RevenueCat endpoint returns active subscription count?
    answer: >-
      GET /v2/projects/{id}/metrics/overview. It returns the same figures the
      dashboard shows, including active subscriptions, active trials, MRR and
      revenue, in one call with no paging.
  - question: Does RevenueCat count grace-period subscriptions as active?
    answer: >-
      Yes. Paid subscriptions that have been cancelled or are in a billing grace
      period count until they actually expire. That is the right call: a retry
      in progress is still a customer, and excluding them would make the count
      dip whenever a store renewal queue is slow.
  - question: How do I get a list of RevenueCat subscribers?
    answer: >-
      Build it yourself from webhooks. Subscribe to INITIAL_PURCHASE, RENEWAL,
      CANCELLATION and EXPIRATION and maintain your own table. It is the only
      reliable way to hold a current subscriber list, and it lets you query it
      however you like.
---

## Is there a RevenueCat endpoint for active subscribers?

Not the one you want. This is the single most searched RevenueCat API
question and the honest answer is that no endpoint returns "every subscriber
who is currently active" as a list.

What exists is three different things, and picking between them is the
actual task.

## The three options

**v1 subscriber lookup.** `GET /v1/subscribers/{app_user_id}` returns one
customer with their entitlements and subscriptions. It is designed for
checking access for a specific user, and it is the right call inside your app
or your backend when somebody signs in.

It is the wrong call for counting, because you need the list of ids before
you can look any of them up, and RevenueCat will not give you that.

**v2 list endpoints.** `GET /v2/projects/{id}/customers` pages customers, and
there are subscription endpoints under v2 as well. The catch is coverage:
the v2 subscription listing is oriented around subscriptions RevenueCat
processes directly, and store-managed subscriptions from App Store and Play
Store do not all surface there the way people expect. Read it as a customer
directory rather than as a subscriber count.

**The Overview metrics.** `GET /v2/projects/{id}/metrics/overview` returns
the figures the dashboard shows, including active subscriptions, active
trials, MRR and revenue. One call, no paging, and it agrees with the
dashboard.

For a count, this is the answer. For a list, there is no answer.

## The call that actually counts

```bash
curl -s 'https://api.revenuecat.com/v2/projects/proj1ab2c3d4/metrics/overview' \
  -H 'Authorization: Bearer sk_...'
```

The response carries a `metrics` array of objects with an `id` and a `value`.
Read them by id rather than by position, because the order is not a contract
and a new metric appearing in the middle would silently shift everything
after it.

```js
function metric(body, id) {
  return body.metrics?.find((m) => m.id === id)?.value ?? null;
}

const activeSubs = metric(body, "active_subscriptions");
const activeTrials = metric(body, "active_trials");
const mrr = metric(body, "mrr");
```

## What active subscriptions includes

Paid subscriptions active right now, including ones that have been cancelled
or are in a grace period, until they actually expire. Trials are not
counted, which is why there is a separate trials figure.

Including grace-period subscriptions is the right call: a billing retry in
progress is still a customer, and excluding them would make your count dip
every time Apple's renewal queue is slow.

## Use a v2 secret key

v1 and v2 keys are different objects. A v1 key against a v2 endpoint returns
401, which reads like a revoked key rather than a wrong version. Create a new
secret key in project settings, select V2, and give it read permissions.

Project-scoped, so the project id in the URL has to be the one the key
belongs to.

## If you really need the list

Record it yourself. Subscribe to RevenueCat's webhooks for `INITIAL_PURCHASE`,
`RENEWAL`, `CANCELLATION` and `EXPIRATION`, and maintain your own table of
who is active. That is the only reliable way to hold a current subscriber
list, and it has the useful side effect of letting you query it however you
like.

## Or read the count off the notch

Notch Metrics reads the overview endpoint and reports
[RevenueCat active subscriptions](/sources/revenuecat/active-subscribers) and
[active trials](/sources/revenuecat/trials) in the MacBook notch, with
[MRR](/sources/revenuecat/mrr) and
[revenue](/sources/revenuecat/revenue) beside them.

One connection, a v2 secret key that never reaches your Mac.
[Everything RevenueCat reports](/sources/revenuecat), or
[download Notch Metrics](/download).
