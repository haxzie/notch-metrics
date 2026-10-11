---
title: "How to get new users from Amplitude"
description: "New users is first-seen, and first-seen depends on when you started tracking. What the number counts, and the backfill that breaks it."
date: 2026-10-11
author: Notch Metrics
tags: [amplitude, users, api]
pillar: amplitude-active-users-on-your-mac
faq:
  - question: How do I get new users from the Amplitude API?
    answer: >-
      Call /api/2/users with m=new instead of m=active. Everything else about
      the request and the response shape is identical.
  - question: What counts as a new user in Amplitude?
    answer: >-
      Somebody whose first event Amplitude ever saw falls inside the window.
      That is usually the first page or screen they opened, not a signup, and it
      can be long before they created an account.
  - question: Why did my Amplitude new user count spike after a migration?
    answer: >-
      Probably an identity change. If how user_id is derived changes, every
      returning user looks brand new, and the spike is indistinguishable from a
      successful campaign.
  - question: Do anonymous visitors count as new users in Amplitude?
    answer: >-
      Yes. Amplitude creates a device id for a visitor with no user_id and that
      device is a user. Identity merging later ties the device to the account,
      taking the earlier first-seen date.
  - question: What should I read alongside Amplitude new users?
    answer: >-
      Active users. New rising while active stays flat means acquisition works
      and nothing sticks, which is the leakiest and most common shape. Neither
      number means much alone.
---

## The call

The same endpoint as active users, with one letter changed.

```bash
curl -s -u "$API_KEY:$SECRET_KEY" \
  'https://amplitude.com/api/2/users?start=20261001&end=20261007&m=new&i=1'
```

`m=new` rather than `m=active`. Everything else is identical, including the
response shape, which puts your numbers at `data.series[0]`.

## What new means

A user whose first event Amplitude ever saw falls inside the window.

Not somebody who signed up in the window. Not somebody who became a customer.
First event, which is usually the first page they loaded or the first screen
they opened, and which may be long before they created an account.

That makes it a top-of-funnel number. If you want signups, that is a specific
event you instrumented and the segmentation endpoint counts it.

## The thing that breaks the number

Amplitude decides "first ever" from the data it holds. Three situations make
that misleading.

**The day you added Amplitude.** Every existing user you have is new on the
day tracking went live. Your new user chart has a cliff at the start that is
not a launch.

**A backfill.** Importing historical events moves users' first-seen dates
backwards, which rewrites your new user history. Figures you reported last
month change.

**An identity change.** If you alter how `user_id` is derived, every
returning user looks brand new. A migration that changes id format produces a
new-user spike indistinguishable from a successful campaign.

That last one is worth saying out loud before anybody celebrates.

## Anonymous users count

Amplitude creates a device id for a visitor with no `user_id`, and that
device is a user. So new users includes people who loaded one page and never
came back.

Over time, identity merging ties a device to a user once they identify, and
the first-seen date follows the earliest of the two. That is correct and it
means a user's first-seen date can be earlier than their account creation
date, which looks wrong on a join and is not.

## New against active is the useful pair

Neither number means much alone.

- **New flat, active rising.** Retention is improving. Existing users are
  coming back more.
- **New rising, active flat.** Acquisition is working and nothing is
  sticking. The leakiest and most common shape.
- **Both rising together.** Growth.
- **New rising, active falling.** You are buying traffic that leaves faster
  than it arrives.

Place them side by side or the series tells you nothing you can act on.

## Daily, weekly and monthly disagree

A weekly new-user figure is not the sum of seven daily ones, for the same
de-duplication reason that applies to active users. Somebody whose first
event is on Tuesday is new once in the week, and once on Tuesday.

In the new-user case the figures happen to be closer than they are for active
users, because a person is only ever new once overall. They still are not
equal, because the window boundary moves.

## In the notch

Notch Metrics reports
[Amplitude new users](/sources/amplitude/new-users) as users first seen in
the window, daily, weekly or monthly, bucketed in your Amplitude project's
own timezone.

Place it beside [active users](/sources/amplitude/active-users) and
[events](/sources/amplitude/events) and the three say which of the four
shapes above you are in.
[Everything Amplitude reports](/sources/amplitude), or
[download Notch Metrics](/download).
