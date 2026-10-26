---
title: Quickstart
description: Build a custom app and get its first widget into your notch, in about ten minutes.
summary: From an empty folder to a widget in the notch.
section: start
order: 1
date: 2026-10-26
---

A custom app is one folder holding two files. This builds one that reads a
public API, so there is no key to set up on the way.

## 1. Make the folder

```bash
mkdir -p ~/notch-apps/npm-downloads
cd ~/notch-apps/npm-downloads
```

The folder name has to match the `id` in the manifest.

## 2. Write the app

`connector.mjs` is the whole app. There is no manifest to write.

```js
import { createApp, createMetric } from "@notchmetrics/core";

const downloads = createMetric({
  id: "downloads",
  label: "Downloads",
  unit: "count",
  series: { granularities: ["day"] },
  methodology: "Downloads reported by the npm registry for the window.",
  params: [{ key: "package", label: "Package", type: "string" }],

  async fetch(ctx, request) {
    const name = request.params.package ?? "react";
    const response = await ctx.http(
      `https://api.npmjs.org/downloads/range/${request.from}:${request.to}/${name}`,
    );
    if (!response.ok) throw new Error(`The registry returned ${response.status}.`);

    const body = await response.json();
    const points = body.downloads.map((day) => ({ t: day.day, v: day.downloads }));
    return { value: points.reduce((total, point) => total + point.v, 0), points };
  },
});

export default createApp({
  id: "npm-downloads",
  name: "npm downloads",
  description: "Download counts for a package on the npm registry.",
  icon: { type: "symbol", name: "shippingbox.fill" },
  allowedHosts: ["api.npmjs.org"],
  refreshIntervalSeconds: 3600,
  metrics: [downloads],
});
```

`params` puts a Package field on the widget, so one app serves a tile per
package.

Network access goes through `ctx.http`. A bare `fetch` bypasses the host
allowlist, so it is refused.

There is no `verify` here. This API needs no credential, so there is nothing
to prove.

## 3. Build the manifest

```bash
npx @notchmetrics/core build
```

```
Wrote /Users/you/notch-apps/npm-downloads/manifest.json
1 metric: downloads
```

That reads your code and writes `manifest.json` beside it. Run it again after
any change to the app or its metrics.

The file exists so Notch Metrics can read what an app asks for without
running it. Your code stays the only place you edit.

## 4. Load it

Open Settings, then Custom Apps, then Load app, and pick the folder.

Notch Metrics copies it into its own folder and validates the manifest. A
manifest that fails is refused with the reason.

Enable the app with the switch.

## 5. Add the widget

Open the notch, add a widget, and find npm downloads under Custom.

Type a package name in the Package field. The tile fills on the next refresh.

## What to read next

[The manifest](/docs/connector-manifest) covers every field. [The
code](/docs/connector-code) covers the context object and what to return for
each kind of number.

If you want your editor to check the shapes as you type, [development
setup](/docs/development-setup) covers the types package.
