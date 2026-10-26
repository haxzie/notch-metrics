# @notchmetrics/core

## 0.2.0

### Minor Changes

- [`8ff2372`](https://github.com/haxzie/notch-metrics/commit/8ff23725db81c1df93dc7275a1dbcd4c2f1354b6) Thanks [@haxzie](https://github.com/haxzie)! - Declare a connector in code and generate its manifest from it.

  `createMetric` puts a metric's description and the code that answers it in one
  object. `createApp` takes those plus what the app is, and `notch-metrics build`
  writes `manifest.json`. A metric no longer exists twice, once as JSON and once
  as a branch in a `fetchMetric` that switched on its id.

  The build runs on the author's machine, so the Mac app still reads what an app
  asks for without executing any of it. `allowedHosts`, `auth` and
  `hostCredentials` stay on the app because they are grants; labels, units and
  shapes moved to the metric because they are not.

  A connector exporting `verify` and `fetchMetric` still runs.
