---
title: Development setup
description: What you need on your Mac to build a custom app, and how to get type checking while you write one.
summary: Node, the types package, and the edit and reload loop.
section: start
order: 2
date: 2026-10-26
---

A custom app is plain JavaScript and needs no build step. The setup below is
what makes writing one comfortable.

## What you need

Notch Metrics on Apple silicon, macOS 14 or later.

Node 20 or later on your Mac. Notch Metrics runs your connector with the Node
you already have, so an app that works at your terminal works in the notch.

That is the whole requirement. No bundler, no package manager, no
dependencies.

## Finding Node

A menu bar app does not inherit your shell's `PATH`, so Notch Metrics looks
for Node at absolute paths.

It checks Homebrew on Apple silicon and Intel, then `/usr/bin`, then every
version manager install side by side: nvm, fnm and Volta. Where a version
manager holds several, Notch Metrics takes the newest.

Set `NOTCH_NODE_PATH` to override that with an exact binary. It wins over
everything else and is never second guessed.

## The package

```bash
npm install --save-dev @notchmetrics/core
```

It gives you two things: `createApp` and `createMetric`, which your editor
checks as you type, and the `build` command that writes `manifest.json` from
your code.

Nothing is imported at run time. The runner supplies the context object, so
the file you ship runs with no `node_modules` beside it.

Writing TypeScript is fine. Build it to a single `connector.mjs` with the
default export and ship that.

## The loop

Edit the file in your own folder.

```bash
npx @notchmetrics/core build
```

Then open Settings, then Custom Apps, and pick Reload from the app's three
dot menu.

Run the build after any change to the app or its metrics. A change to the
body of a `fetch` needs no rebuild, because the manifest does not describe
it.

The build is also the check. It validates every field against the schema the
Mac app uses, reports all the problems at once, and writes nothing until they
are fixed.

Notch Metrics runs a copy it owns, so an edit in your project folder takes
effect when you reload it. That is what stops a build in a folder you are
still editing from silently changing an app you already enabled.

## Seeing what went wrong

A metric that throws puts its message on the tile. Throw with a sentence
somebody can act on, because `The API returned 429.` is useful and `undefined
is not an object` is not.

A run that passes `timeoutMs` is killed and the tile says so. Every metric in
one refresh shares that budget, so measure a real run before raising it.

## The log

Every app writes its own log. Open it from the app's three dot menu, under
Open logs, which shows the file in Finder.

```
~/Library/Application Support/NotchMetrics/logs/custom-apps/<app-id>.log
```

Each run appends a block.

```
=== 2026-10-26 16:04:11  fetch  downloads  154ms
  ok downloads value=42444710 points=7
  http GET api.npmjs.org 200 1051ms
  log asked for react
```

It records what was asked for, what each metric answered, every host called
with its status, and anything passed to `ctx.log`. A failure carries the
message your code threw.

```
=== 2026-10-26 16:09:02  fetch  stars  88ms
  failed stars [runtime] The API returned 429.
  http GET api.github.com 429 81ms
```

A host your manifest does not allow shows as blocked, which is the one
mistake the tile cannot explain on its own.

```
  http GET evil.example.com blocked 0ms
```

The file keeps the last two thousand lines. Paste the relevant block into
your agent to get a connector fixed.

## Authoring with an assistant

The [introduction](/docs) has a prompt that points a model at one file
carrying the manifest schema, the runtime contract and a worked example.
