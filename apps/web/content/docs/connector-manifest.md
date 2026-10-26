---
title: The app and its manifest
description: createApp declares what the app is and what it may reach. The manifest is generated from it.
summary: createApp, the grants it declares, and the generated manifest.
section: apps
order: 2
date: 2026-10-26
---

`createApp` declares what the app is, what it may reach, and which metrics it
offers. Everything in this page is a field on that call.

```js
export default createApp({
  id: "my-app",
  name: "My app",
  description: "What this app reads, in a sentence.",
  icon: { type: "symbol", name: "shippingbox.fill" },
  allowedHosts: ["api.example.com"],
  auth: [{ key: "api_key", label: "API key", type: "secret" }],
  metrics: [activeUsers, revenue],
});
```

## Why there is still a manifest

`npx @notchmetrics/core build` writes `manifest.json` beside your code.

Notch Metrics reads that file to learn what an app asks for **before** it runs
a line of the app. That is what lets the settings row show you the hosts and
the credentials, and what makes enabling the app a decision you can actually
make. Working it out by running the app would be the wrong way round.

So the code is the source and the file is generated. You edit one place.

Run the build again after changing the app or any of its metrics. A manifest
that has drifted from the code is the thing this command exists to prevent.

## What the build checks

Every field is validated against the same schema the Mac app holds the
manifest to. A build that passes produces a file the app will load.

Mistakes are reported together, named by the metric they are in.

```
Metric "Bad Id With Spaces" is not valid:
  id: A metric id is lower-case letters, digits and underscores, starting with a letter.
  shortLabel: Too big: expected string to have <=12 characters
  methodology: Too small: expected string to have >=1 characters
  params.0.type: Invalid option: expected one of "string"|"secret"|"select"|"url"|"boolean"
```

Each metric is checked as it is created, so the error names the metric you
wrote rather than a position in an array. Nothing is written until every
check passes.

## The app

| Field         | What it does                                                      |
| ------------- | ----------------------------------------------------------------- |
| `id`          | Lower case letters, numbers and hyphens. Matches the folder name. |
| `name`        | What the Custom Apps list shows.                                  |
| `description` | One sentence.                                                     |
| `version`     | Yours to display. Notch Metrics never upgrades a custom app.      |
| `author`      | Optional.                                                         |

## The icon

```js
icon: { type: "symbol", name: "shippingbox.fill", tint: "#D97757" }
```

Three forms. `symbol` names an SF Symbol and suits most apps, because it is
vector and needs no file. `emoji` takes one character. `file` takes the name
of an image inside the app's folder, never a path and never a URL.

An unknown symbol name draws the generic mark, so a typo costs an icon and
nothing else.

## Hosts

```js
allowedHosts: ["api.example.com"];
```

Every host the app may contact. Nothing else is reachable through `ctx.http`.

A host, not a URL. `https://api.example.com/v1` is refused, because this list
is the containment boundary and a typo in it should fail loudly.

## Credentials

```js
auth: [{ key: "api_key", label: "API key", type: "secret" }];
```

Each entry becomes a field in the app's settings row. A `secret` is stored in
your Keychain and shown masked. The other types are `string`, `select`, `url`
and `boolean`.

Omit `auth` for an app that needs nothing. There is no mode to set: an app
with fields asks for them, and an app with none does not.

## Borrowed sign ins

```js
hostCredentials: ["claude_code_oauth"];
```

The narrow exception to typing your own key: a token already on your Mac that
rotates too often to paste. Notch Metrics reads it and hands it to the app.

An app receives one only by naming it here, and the settings row says which,
so you can see what an app will be given before you enable it.

## Timing

```js
refreshIntervalSeconds: 300,
timeoutMs: 8000
```

`refreshIntervalSeconds` runs from 60 to a day, and defaults to 300. Notch
Metrics floors it regardless, because an app that runs every second gets your
API key rate limited and flattens a battery doing it.

`timeoutMs` runs from 1000 to 20000 and defaults to 8000. Every metric in one
refresh shares the budget, so measure a real run before raising it.

## The numbers

`metrics` takes the objects `createMetric` returns. Each one carries its own
`fetch`, so a metric's name, its unit and the code that answers it sit
together. See [the code](/docs/connector-code).
