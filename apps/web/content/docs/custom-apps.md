---
title: How custom apps work
description: What a custom app is, where it runs, what it can reach, and what enabling one approves.
summary: Where an app runs, what it can reach, and what enabling it approves.
section: apps
order: 1
date: 2026-10-26
---

A custom app puts a number Notch Metrics has no connector for into your notch.
A figure from your own admin API, downloads of a package you publish, rows
from a service nobody else uses.

It is one folder holding two files.

```
my-app/
  manifest.json    what the app is, and every number it offers
  connector.mjs    two exported functions
```

The folder lives on your Mac. Nothing in it is uploaded.

## One app, many widgets

A custom app is one piece of code holding one credential. Every number it
declares is a metric of that app, and each becomes a widget you can add.

One API key, one app, as many widgets as you want from it.

## Where it runs

On your Mac, with the Node you already have, as a separate process per refresh.

Every metric in one refresh runs in the same process. The whole batch shares
the manifest's `timeoutMs`, and a run that passes it is killed.

## What it can reach

The manifest lists every host the app may contact. Nothing else is reachable
through `ctx.http`.

Requests go out over https. Private and loopback addresses are refused.
Redirects are followed three deep and the host is checked again on every hop,
so a server that redirects to a host outside your list never receives your
credential.

A response is capped at 4 MB.

## Contained, not sandboxed

The host allowlist bounds where a custom app can send data. The code still
runs on your Mac as you, with your file system.

Read a custom app before you enable it, exactly as you would read any script
you are about to run.

## Credentials

A key you type into an app's settings row is stored in your Keychain and
passed to the app at run time. Only the keys the manifest declares are passed,
so a credential the app never asked for is not readable by it.

An app can also borrow a sign in already on your Mac, where the token rotates
too often to paste. It receives one only by naming it in the manifest, and the
settings row says which, so you can see what an app will be given before you
enable it.

## What enabling approves

Enabling an app approves three things: the hosts it may reach, the credentials
it asks you for, and any sign in it borrows.

Edit the code and it keeps running. Widen any of those three and the row asks
again, naming what is newly wanted. A version bump or a new icon is not a
question anybody can answer, so Notch Metrics does not ask one.

## The log

Every app writes its own, at
`~/Library/Application Support/NotchMetrics/logs/custom-apps/<app-id>.log`.
Open it from the three dot menu, under Open logs.

Each run records what was asked for, what each metric answered, every host
called with its status, and anything the app passed to `ctx.log`. See
[development setup](/docs/development-setup) for what a block looks like.

## Reloading and removing

The three dot menu on each row reloads the app from disk, opens its log, or
removes it.

Notch Metrics runs a copy it owns, so reload is what picks up an edit. Removing
deletes that copy and every widget built on it, and leaves the folder you
loaded it from untouched.
