# @notch/db

## 0.1.0

### Minor Changes

- [`ad1b0ff`](https://github.com/haxzie/notch-metrics/commit/ad1b0ff02da8e761104919882b2fabe87898997f) Thanks [@haxzie](https://github.com/haxzie)! - Notifications, and a notification centre in the notch

  Providers now declare what they can notify about in their manifest, so a new
  provider's notifications ship with a Worker deploy and no app release — the same
  property widgets already have. The Worker evaluates the enabled ones on the cron
  it already runs, reusing the series it was fetching anyway, so the feature costs
  no extra provider calls.

  The Mac shows them in a two-column pane inside the notch, connections on the
  left. A new one drops out of the notch as a round app mark, falls clear, then
  opens into a card with the headline and a line of detail — and goes back the
  same way, closing to a circle before it rises, so it reads as being swallowed
  rather than deleted. Clicking it opens the provider's own dashboard.

  There is no `UNUserNotificationCenter` involved and so no permission prompt, no
  entitlement and no Info.plist change: the notch is already on screen, so the app
  owns the presentation.

  Honest about what it is: notifications arrive within about five minutes for
  polled providers, and nothing is delivered while the Mac is asleep. This is a log
  you catch up on, not a pager.

  Per-connection notification toggles live in Connections, beside rename and
  disconnect: what Stripe is allowed to tell you is a fact about your Stripe
  connection rather than an app-wide preference. The Notifications pane keeps what
  genuinely is app-wide — whether banners show, how long they stay, the sound,
  quiet hours — and links across.

  A notification can also make a sound. Silent by default — adding audio to every
  existing install on an update reads as a bug rather than a feature — with a
  curated shortlist in Settings that previews each one as you select it.

  Fixes a latent fault in `AppSettings` while adding preferences to it. It decoded
  through Swift's synthesised initialiser, which ignores property defaults and
  throws on any key the file does not have, so the first release to add a
  preference would have silently reset every _existing_ user's launch-at-login,
  display choice, hover timings and approved plugins. It now decodes field by
  field, and a test pins it with a real pre-notifications settings file.

  Also moves the existing five-minute metrics refresh onto the same energy gate.
  It previously ran unconditionally — on battery, in Low Power Mode, with the lid
  shut — and `stopRefreshing()` had no callers. On an eight-hour sleep that was
  ~96 wake-ups and 96 hits against the user's provider rate limit.
