# @notch/schemas

## 0.3.0

### Minor Changes

- [`95bf1a7`](https://github.com/haxzie/notch-metrics/commit/95bf1a7203615230bfdba95c12eee31eb224ea83) Thanks [@haxzie](https://github.com/haxzie)! - Remove the HubSpot and Intercom connectors.

  Both were declared and never implemented: `status: "coming_soon"` since the
  day the catalogue was added, every metric throwing `notImplemented`, and
  `connectable()` filtering them out. Nobody has ever connected one, so there
  are no rows, no widgets and nothing to migrate — which is the only reason
  this is a deletion rather than a deprecation.

  They were also the only two connectors in the CRM category, so the category
  goes with them along with the six metric ids nothing else declared —
  `contacts`, `new_contacts`, `open_deals`, `won_deals`, `pipeline_value` and
  `open_conversations`. Leaving those behind would have recreated the problem
  `arr` and `conversion_rate` already are: ids in the enum that no provider
  serves, which nothing fails over and nobody notices.

  `ProviderId`, `MetricId` and `ConnectorCategory` all shrink, so this is a
  wire change and `contracts/` is regenerated with it. No golden fixture moved
  — none of them named a removed value — and the Swift models read these as
  strings with a fallback, so an installed app meeting the smaller catalogue
  decodes it fine.

  The marketing site loses its Sales layout, which was nine-tenths HubSpot and
  Intercom. Its own note said leaning on "Soon" connectors was deliberate
  because it showed where the product was going; with them gone it showed where
  it is not. Rebuilding it from revenue widgets would have made a second
  Founders layout, so it went instead. The hero glyph that was HubSpot is now
  Claude, which keeps the hand-placed composition intact.

- [`8ff2372`](https://github.com/haxzie/notch-metrics/commit/8ff23725db81c1df93dc7275a1dbcd4c2f1354b6) Thanks [@haxzie](https://github.com/haxzie)! - Four new widget shapes, and a row layout for wide tiles.

  A gauge draws a ratio inside a filled arc. Split, ranked and ring draw one
  list's categories against each other, each with a key naming as many as the
  tile has room for.

  A one-row tile wider than two columns now reads left to right. Stacked, it put
  the name on top and the figure in the middle and left everything past the
  second column empty.

### Patch Changes

- Updated dependencies [[`8ff2372`](https://github.com/haxzie/notch-metrics/commit/8ff23725db81c1df93dc7275a1dbcd4c2f1354b6)]:
  - @notchmetrics/core@0.2.0

## 0.2.0

### Minor Changes

- [`f98d0a9`](https://github.com/haxzie/notch-metrics/commit/f98d0a9e4ed812288a2353f9c4a9ed3ce894ce16) Thanks [@haxzie](https://github.com/haxzie)! - Charge $9 a month, or $49 a year

  Both prices come down, and the annual saving goes from 53% to 55%. `PLANS` is
  the only place either number is written, so the website, the checkout and the
  desktop upsell cannot quote different figures.

  Dodo holds the authoritative amount. The products there have to be changed to
  match, and until they are, the site quotes a price the checkout will not take.

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

### Patch Changes

- [#3](https://github.com/haxzie/notch-metrics/pull/3) [`eca363b`](https://github.com/haxzie/notch-metrics/commit/eca363ba62ade87c90157c57d50d66dcee447a2d) Thanks [@haxzie](https://github.com/haxzie)! - Notch Metrics updates itself. The Updates pane checks the release feed, offers
  the version it finds, downloads it, checks it and swaps the app over, and a
  coloured chip in the bottom corner of the notch says so without anybody going
  looking in Settings.

  The installing half already existed. What is new is everything that decides
  whether to install anything: a six-hourly poll, the build-number comparison,
  the download with a progress bar, and the states the pane draws. A build this
  Mac cannot run reads as up to date rather than as a failure, a half-written
  download is thrown away rather than offered, and a verified one survives a
  relaunch so quitting mid-update does not mean fetching it again.

  The feed is the Worker's, with the bucket as a fallback for the case the Worker
  is down. A 404 from the Worker is treated as an answer rather than as a reason
  to read the bucket, which is what keeps `PINNED_VERSION` able to pull a bad
  release back.

## 0.1.0

### Minor Changes

- [`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d) Thanks [@haxzie](https://github.com/haxzie)! - Add a RevenueCat connector with six widgets: MRR, revenue over the window with
  a comparison to the window before, active subscriptions, active trials, and
  RevenueCat's 28-day new and active customer counts.

  Connect it with a v2 secret API key that has Charts & Metrics read. A key that
  can also list projects is named after the project; one that cannot works too,
  provided the project ID is typed in. A key that can see several projects is
  asked to pick one rather than having one chosen for it.

  Figures come from RevenueCat's own Overview and revenue endpoints, so they match
  the dashboard. Money arrives as decimals and is converted to minor units per
  currency, so a yen figure is not multiplied by a hundred.

- [`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d) Thanks [@haxzie](https://github.com/haxzie)! - Polar and Paddle are now live connectors, and every payment provider gains a
  Recent payments widget.

  Polar reads MRR, revenue, active, new and churned subscriptions from Polar's
  own metrics endpoint, so the figures match its dashboard, and lists the latest
  paid orders. Paddle totals paid and completed transactions by billing date,
  normalises active subscriptions to a monthly amount for MRR, counts starts and
  cancellations across the subscription book, and lists the latest transactions
  with the customer embedded. Both take an environment alongside the key, since
  neither API lets the host be inferred from the token.

  Recent payments is a list widget: the tile shows the latest ten payments as
  rows, with who paid, what for, how much, and how long ago, rather than a single
  figure. It is available on Stripe, Dodo Payments, Lemon Squeezy, Polar and
  Paddle. A series can now carry rows on the wire; an older app ignores them.

- [`b523d18`](https://github.com/haxzie/notch-metrics/commit/b523d1855426528177e84307ebb8b6b2fed86c03) Thanks [@haxzie](https://github.com/haxzie)! - Dodo Payments gains a One-time sales widget: succeeded payments in the window
  that are not tied to a subscription, with a chart and a comparison to the
  window before. The existing Revenue widget is now called Total revenue, since
  it counts subscription renewals and one-time purchases together.

- [`a8188dc`](https://github.com/haxzie/notch-metrics/commit/a8188dcf86262d3c8e0e494bd60e40c285cb49bf) Thanks [@haxzie](https://github.com/haxzie)! - Add OpenAI and Claude as API-key connectors, under a new "AI" category: token
  volume, request counts and daily spend.

  Each provider is given the metrics it can actually answer for. OpenAI's usage
  report carries a request count and Claude's does not, so Claude offers no
  `api_requests` rather than an invented one.

  Two ways the money goes wrong, written down because both look right: Claude's
  cost report returns a decimal string already in cents, so reading `"123.78912"`
  as dollars overstates the bill a hundredfold, and OpenAI returns a float in
  dollars, which has to round to minor units once per bucket rather than per
  line item.

  Both usage APIs cap a response at 31 daily buckets, so a window is a page
  count, not a call. The walk is bounded at four requests: a 90-day range drops
  its comparison window to stay inside that and keeps the number, and a year is
  refused with a message rather than by the Worker's CPU limit.

  Cost is a separate reach from usage on both admin APIs, so a key that can read
  tokens but not dollars connects with `api_spend` greyed out instead of being
  rejected — but only on a refusal, since `availableMetrics` is written once at
  connect and a transient 503 would hide spend until the user reconnected.

  Both connectors ship their own brand mark on the brand's own tile: OpenAI's
  blossom white on black, Claude's sunburst white on #D97757. simple-icons
  carries neither at the title the sync script would look for, so both are
  committed as overrides rather than derived at build time.
