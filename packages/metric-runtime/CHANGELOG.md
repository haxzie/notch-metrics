# @notch/metric-runtime

## 0.1.0

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

### Patch Changes

- Updated dependencies [[`95bf1a7`](https://github.com/haxzie/notch-metrics/commit/95bf1a7203615230bfdba95c12eee31eb224ea83), [`8ff2372`](https://github.com/haxzie/notch-metrics/commit/8ff23725db81c1df93dc7275a1dbcd4c2f1354b6)]:
  - @notch/schemas@0.3.0

## 0.0.2

### Patch Changes

- Updated dependencies [[`f98d0a9`](https://github.com/haxzie/notch-metrics/commit/f98d0a9e4ed812288a2353f9c4a9ed3ce894ce16), [`ad1b0ff`](https://github.com/haxzie/notch-metrics/commit/ad1b0ff02da8e761104919882b2fabe87898997f), [`eca363b`](https://github.com/haxzie/notch-metrics/commit/eca363ba62ade87c90157c57d50d66dcee447a2d)]:
  - @notch/schemas@0.2.0

## 0.0.1

### Patch Changes

- Updated dependencies [[`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d), [`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d), [`b523d18`](https://github.com/haxzie/notch-metrics/commit/b523d1855426528177e84307ebb8b6b2fed86c03), [`a8188dc`](https://github.com/haxzie/notch-metrics/commit/a8188dcf86262d3c8e0e494bd60e40c285cb49bf)]:
  - @notch/schemas@0.1.0
