---
title: "How to query active users from the Amplitude Dashboard REST API"
description: "Basic auth with two keys, the m parameter that decides everything, and the regional host that makes a good key look revoked."
date: 2026-10-11
author: Notch Metrics
tags: [amplitude, analytics, api]
pillar: amplitude-active-users-on-your-mac
faq:
  - question: How do I authenticate with the Amplitude Dashboard REST API?
    answer: >-
      HTTP Basic auth, with the API key as the username and the secret key as
      the password. Not a bearer token. Both are project-scoped and the secret
      key reads every event in the project, so it belongs on a server.
  - question: What is the Amplitude EU API host?
    answer: >-
      analytics.eu.amplitude.com, against amplitude.com for US. A key pair from
      one region fails against the other with a message that reads like a
      revoked key, so check the host before regenerating credentials.
  - question: How do I get new users instead of active users in Amplitude?
    answer: >-
      Change the m parameter on /api/2/users from active to new. Everything else
      about the call is identical, which means a single character changes your
      metric.
  - question: What date format does the Amplitude API use?
    answer: >-
      YYYYMMDD with no separators, such as 20261001. Not ISO 8601 and not a
      timestamp.
  - question: Why is data.series an array of arrays in Amplitude?
    answer: >-
      Because it holds one entry per segment. With no segmentation there is
      exactly one, so your numbers are at data.series[0]. Reading data.series
      directly as numbers fails with a type error rather than a wrong figure.
---

## Which Amplitude API answers this?

The Dashboard REST API, which is the read-only one. Amplitude also has an
HTTP API for sending events and an Export API for raw data, and neither
answers "how many active users last week".

```bash
curl -s -u "$API_KEY:$SECRET_KEY" \
  'https://amplitude.com/api/2/users?start=20261001&end=20261007&m=active&i=1'
```

## Basic auth with two keys

Not a bearer token. The API key is the username and the secret key is the
password, in HTTP Basic auth.

```js
const auth = Buffer.from(`${apiKey}:${secretKey}`).toString("base64");
const res = await fetch(url, { headers: { Authorization: `Basic ${auth}` } });
```

Both come from project settings and both are project-scoped. The secret key
is a secret in the real sense: it reads every event in the project, so it
belongs on a server and never in a client.

## The regional host

| Region | Host                         |
| ------ | ---------------------------- |
| US     | `amplitude.com`              |
| EU     | `analytics.eu.amplitude.com` |

A US key pair against the EU host fails to authenticate, and the message
reads like a revoked key. People regenerate credentials over this. Check the
host first.

## The m parameter decides what you get

`/api/2/users` returns active or new users depending on one letter.

| `m`      | What it counts                              |
| -------- | ------------------------------------------- |
| `active` | Users with at least one event in the window |
| `new`    | Users seen for the first time in the window |

Everything else about the call is identical, which is convenient and means a
single character typo changes your metric without changing your code shape.

## Dates and intervals

`start` and `end` are `YYYYMMDD` with no separators. Not ISO, not a
timestamp. `20261001`.

`i` is the interval: `1` for daily, `7` for weekly, `30` for monthly. There
is no hourly option, so anything finer than a day is not available from this
endpoint at all.

## The response shape

```json
{
  "data": {
    "series": [[120, 98, 143, 131, 110, 76, 89]],
    "seriesLabels": [0],
    "xValues": ["2026-10-01", "2026-10-02", "..."]
  }
}
```

`series` is an array of series, and with no segmentation there is exactly
one, so the numbers you want are at `data.series[0]`. `xValues` holds the
matching dates.

Reading `data.series` as the array of numbers rather than as the array of
series is the mistake everybody makes once, and it fails with a type error
rather than a wrong number, which is the kind way round.

## De-duplication

The daily series de-duplicates within each day. A weekly figure, asked for
with `i=7`, de-duplicates across the week.

So summing seven daily values does not give you the weekly value. It gives
you something larger, inflated by exactly how much your users come back,
which is the retention you were presumably trying to measure separately.

If you want both, ask twice.

## Event counts use a different endpoint

Active users come from `/api/2/users`. Event volume comes from
`/api/2/events/segmentation`, with its own parameters and the same response
shape. Two endpoints, one shape, which makes a shared parser worth writing.

## Or read it off the notch

Notch Metrics calls this endpoint and reports
[Amplitude active users](/sources/amplitude/active-users),
[new users](/sources/amplitude/new-users) and
[events](/sources/amplitude/events) in the MacBook notch, daily, weekly or
monthly, bucketed in your Amplitude project's own timezone.

Both keys are encrypted on the server and neither reaches your Mac.
[Everything Amplitude reports](/sources/amplitude), or
[download Notch Metrics](/download).
