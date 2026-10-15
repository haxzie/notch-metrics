# @notch/mac

## 0.3.0

### Minor Changes

- [`799e800`](https://github.com/haxzie/notch-metrics/commit/799e8001b57b3ae506a6bfa6b7cda3acb224cdda) Thanks [@haxzie](https://github.com/haxzie)! - The Integrations pane has a search field above the list. It matches a
  connector's name, tagline and keywords as well as its metrics' labels, so
  "mrr" finds the providers that can show you one — the same matching the
  widget browser uses, rather than a second one that disagrees with it.
  Categories with nothing in them drop out while you type.

- [`ac5f044`](https://github.com/haxzie/notch-metrics/commit/ac5f04496d9c803fb9d60a26c63220416c081712) Thanks [@haxzie](https://github.com/haxzie)! - Tiles are clickable. A click opens the number where it lives: the metric's own
  page where the connector declares one — a GitHub tile goes to its repository's
  stargazers, issues or Actions, filtered to the branch the widget names — and
  the provider's dashboard otherwise. The configure pane's new **Opens** field
  overrides both, for anyone whose useful destination is their own board rather
  than the provider's.

  Connectors declare `dashboardUrl`, and a metric may declare a `linkTemplate`
  whose `{param}` placeholders the widget's own parameters fill. Both are
  catalogue fields, so a provider that moves its dashboard fixes every existing
  tile with a Worker deploy rather than an app release.

- [`a7a79c7`](https://github.com/haxzie/notch-metrics/commit/a7a79c7f5e14a07ca8f1e4d1576d4386af3a1380) Thanks [@haxzie](https://github.com/haxzie)! - A GitHub CI widget: point it at a repository and, if you want, one branch, and
  it lists the last ten Actions runs newest first, each with its outcome as an
  icon — passed, failed, still running, or skipped.

  List rows now carry a `state` beside the provider's own `status`, so a tile can
  draw an outcome without matching on a provider's vocabulary; a metric can also
  declare `freshnessSeconds`, which this one sets to a minute. Without it a CI
  feed would inherit the daily bucket's fifteen-minute cache and could report a
  build that had since gone red.

  Public repositories only, for now: this connection asks GitHub for
  `public_repo`, because the read-only alternative for private ones does not
  exist for an OAuth app.

- [`a3e451f`](https://github.com/haxzie/notch-metrics/commit/a3e451fda95d9d3db175e407a9ccefd82d241ba4) Thanks [@haxzie](https://github.com/haxzie)! - The app now keeps a log on disk at
  `~/Library/Application Support/NotchMetrics/logs/app-<date>.log`: every
  request with its status and timing, every failed widget with the server's
  own reason, and the build and server it started against. Five days are
  kept. Anything shaped like a token or a key is blanked before it is
  written.

  A tile that fails on one range and not another, or only on one person's
  account, previously left nothing behind to look at — the unified log needs
  Console.app and cannot be handed to anybody.

  Switching a widget's range also no longer leaves the previous range's number
  on screen when the new one fails. The last good figure is still held through
  a provider blip, but only while it answers the same question; a 30-day total
  under a title reading "7d" is worse than the error it was standing in for.

- [`07541c2`](https://github.com/haxzie/notch-metrics/commit/07541c2304d07ca3fdbd7937e8321cd552e8bf90) Thanks [@haxzie](https://github.com/haxzie)! - Refresh the numbers that can actually move, and say when you are

  `MetricDescriptor.freshnessSeconds` existed but only GitHub's CI feed used it;
  everything else sat on the granularity's fifteen minutes. Now every metric that
  moves faster than its bucket says so.

  Payments, revenue, orders and refunds re-read every 60s — a payment is an event
  rather than a figure, and a feed of them is the one tile somebody watches
  _because_ it changes. Subscription figures every 3 minutes, developer counts
  every 2, spend and CRM every 5.

  Product analytics, Search Console and YouTube are deliberately untouched. Their
  data is delayed at the source — Search Console "runs two to three days behind",
  in this repository's own words — so a faster poll spends a daily quota to get
  the identical number back. The connector is what knows how fast its data moves,
  which is why this lives on the descriptor rather than in a table keyed on
  `MetricId`: YouTube's `revenue` and Stripe's are not the same number.

  The client follows, or the TTL is academic: 30s with the notch open, 60s on AC,
  180s on battery, and unchanged under Low Power Mode, thermal pressure, a
  metered network or sleep. A faster poll costs a cached round trip rather than
  somebody's rate limit — the TTL is what bounds provider calls, whatever the
  client asks for.

  Tiles also show a small spinner in the corner the share icon uses while a fetch
  is in flight. Refresh deliberately keeps the last number on screen rather than
  blanking the tile, so until now nothing said a figure was being checked at all.

- [`87a4447`](https://github.com/haxzie/notch-metrics/commit/87a4447e8e6010d49720749663928308557a59b9) Thanks [@haxzie](https://github.com/haxzie)! - The notch now gets out of the way when an action opens a window somewhere
  else. Connecting an account, signing in and opening Settings all used to
  leave the panel pinned on top of the browser tab or window they had just
  brought forward.

  A connect flow started from the notch also comes back to it. Finishing one
  always landed on the Settings Integrations pane, which threw away the widget
  you were half-way through configuring; now it reopens on the pane you left,
  and only a flow started from Settings stays in Settings.

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

### Patch Changes

- [`046c445`](https://github.com/haxzie/notch-metrics/commit/046c4455e99d0653fc83e675e9c40058acda5114) Thanks [@haxzie](https://github.com/haxzie)! - Line the account picker up with the fields above it

  A SwiftUI pop-up button does not fill the width it is given: it hugs its title
  and centres inside the slot. The 200pt frame that lines the picker up with the
  Name field was therefore leaving half the spare width as a gap to its right,
  and putting the control's edge somewhere different from every text field in
  the pane. Trailing alignment puts it back on the same line.

- [`a99fa5b`](https://github.com/haxzie/notch-metrics/commit/a99fa5b2a15a57a942f6de809dd74bc4d4cc5071) Thanks [@haxzie](https://github.com/haxzie)! - Changing a widget's settings now visibly refetches it. The tile drops to its
  loading skeleton — or to the last number it has for the range you picked —
  instead of leaving the previous window's figure sitting there, and the
  request for the settings you just moved off is cancelled rather than left to
  land on top of the new one. Rapid changes coalesce into one fetch instead of
  one per keystroke.

- [#3](https://github.com/haxzie/notch-metrics/pull/3) [`eca363b`](https://github.com/haxzie/notch-metrics/commit/eca363ba62ade87c90157c57d50d66dcee447a2d) Thanks [@haxzie](https://github.com/haxzie)! - The download button goes through the release feed rather than reading the
  bucket directly, so withholding a release withholds it from the website as well
  as from the app. Release notes are at notchmetrics.com/changelog, generated
  from the app's own changelog.

- [`4ada868`](https://github.com/haxzie/notch-metrics/commit/4ada8686f1d0312b61e127600b03d6ecc11b666f) Thanks [@haxzie](https://github.com/haxzie)! - Fix widget ranges erroring on the AI connectors. A widget froze its bucket
  when it was created — the first one its metric listed, which is `hour` for
  both OpenAI and Claude — and kept sending it as the range moved, so a
  90-day tile asked for ninety days of hourly buckets and the connector
  refused a walk it could not finish. The bucket now follows the range, the
  way the server and the range picker already assumed.

- [`6c8cb2c`](https://github.com/haxzie/notch-metrics/commit/6c8cb2c88390b25559d83361fd09c4d315514f53) Thanks [@haxzie](https://github.com/haxzie)! - "Mark all read" in the notification centre now actually marks the rows read.
  The inbox held read state alongside the notifications rather than on them, and
  every row, badge and bold title reads it off the notification itself, so the
  button changed only the count in the sidebar and left the list looking
  untouched. Marking one connection read also told the server to clear the whole
  inbox, which another Mac would then agree with.

- [`4f0ae49`](https://github.com/haxzie/notch-metrics/commit/4f0ae493a06d3fee928830337b84cf3bc0b7e3a5) Thanks [@haxzie](https://github.com/haxzie)! - Steadier resize handle: the pointer turns into a resize cursor the first time
  it reaches the handle rather than the second, the panel's bottom edge no longer
  eases and snaps on two clocks while the handle is held, and letting go settles
  onto the row instead of jumping to it.

  The "+3 below" label is now a button — a chevron centred just above the handle
  that scrolls down a screenful, and hides once the last widget is in view.

- [`b1ad4ea`](https://github.com/haxzie/notch-metrics/commit/b1ad4eaec4d2eed0ff1491d92e24ec06cae4c10d) Thanks [@haxzie](https://github.com/haxzie)! - The range picker now offers only the ranges a metric can actually answer
  for. Every connector has declared which buckets its metrics support since
  the first one shipped, and nothing read it — all five ranges were offered
  for everything, so picking one the metric could not serve came back as an
  error on the tile. On the AI connectors that was "12m" on any metric and
  "24h" on spend, which both report once a day. A widget already saved on a
  range its metric cannot serve is moved to the nearest one that works when
  its settings are opened.

  Changing a setting no longer resets the widget's size. The configure pane
  held a copy of the widget taken when it opened and wrote the whole copy back
  on every edit, so resizing a tile with the pane still open and then touching
  any control sprang it back to the size it had been.

## 0.2.0

### Minor Changes

- [`7a72666`](https://github.com/haxzie/notch-metrics/commit/7a72666b9d9c95c4260a8e73721285d21caa752e) Thanks [@haxzie](https://github.com/haxzie)! - A GitHub connection is now the account, not one repository.

  Connect GitHub once and pick the repository on each widget, so a notch can
  watch several repositories without a connection each. Widgets made before this
  keep the repository their connection was created with. Adds a Followers widget,
  which reads the account and needs no repository.

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

- [`45a2de0`](https://github.com/haxzie/notch-metrics/commit/45a2de03263163460e07a72ec40b7b9d87b6a15e) Thanks [@haxzie](https://github.com/haxzie)! - The notch shows real numbers. Widgets now refresh from the API in one batched
  request on launch, every five minutes, and immediately after one is added.
  The seeded Stripe tiles are gone — a new notch starts empty and says so — and
  Custom Metrics is parked until it is revisited.

- [`99fe84f`](https://github.com/haxzie/notch-metrics/commit/99fe84f47eb378a7665ce83914790e4893c83191) Thanks [@haxzie](https://github.com/haxzie)! - Widgets resize by dragging handles on their corners and edges, to any span
  that fits the grid, instead of a button that cycled four presets. Edit mode
  has a proper dot grid behind opaque cards. Nothing can overlap.

- [`fd52e62`](https://github.com/haxzie/notch-metrics/commit/fd52e624faa11fdc59596f6c627ee3dab6a09f4d) Thanks [@haxzie](https://github.com/haxzie)! - Added an Integrations pane listing every connector we know about, grouped by
  what it measures, each with its own icon and a single Connect button. Connect
  opens the browser to finish authenticating and the app picks the connection up
  as soon as it lands.

- [`a80b93a`](https://github.com/haxzie/notch-metrics/commit/a80b93ae2dd2fc7e40626aba263951056e831f9a) Thanks [@haxzie](https://github.com/haxzie)! - Browse and add widgets inside the notch. Add Widget now opens a sidebar, a
  search field and the widget list in the notch itself instead of a separate
  window at the bottom of the screen, and a widget is added by clicking it
  rather than dragging it across the display. The configure pane that follows
  commits with Add, and Cancel takes the new widget back out.

  Signed out, the notch opens on a sign-in panel — a line of explanation and
  one blue Sign in button — instead of a grid of tiles each reading "Sign in".

  Signing in refreshes everything built from the connections list: the Apps
  pane, the connections list, the widget browser and the configure pane's
  Account picker, instead of leaving the signed-out answer on screen. A widget
  whose provider has exactly one account is pointed at it, so tiles added
  before signing in stop reading "Connect Stripe" with Stripe connected; one
  whose provider has several says "Pick a connection" instead.

  A tile's hover badges — share, configure, remove — are dark frosted glass
  with a larger glyph, instead of a small white disc with a glyph too small to
  recognise.

  Double-clicking a widget enters edit mode with that tile selected, and
  pressing Delete removes the selected widget. Edit mode was otherwise a
  half-second long press nobody finds, or a button at the other end of the
  header from the tile being moved.

- [`448eb7d`](https://github.com/haxzie/notch-metrics/commit/448eb7d04bb407d0c110dfa356c360002717037c) Thanks [@haxzie](https://github.com/haxzie)! - The notch is a grid only. The list view, its toggle and everything that
  existed for it are gone.

- [`250fd8b`](https://github.com/haxzie/notch-metrics/commit/250fd8b7a89d12febd6d62564951bc9872a58da4) Thanks [@haxzie](https://github.com/haxzie)! - Added a list view, grouped by the app each number comes from, and made every
  widget belong to an app rather than guessing from its metric name. The header
  toggles between grid and list; the grid says how many widgets it could not fit
  and offers the view that can.

  Hover now opens and closes instantly, and closing is governed by the panel
  rather than by the notch strip — moving down into the panel no longer shuts it.

- [`c804206`](https://github.com/haxzie/notch-metrics/commit/c8042068eaf26eaa39f97c5850ff8b2cce434f9b) Thanks [@haxzie](https://github.com/haxzie)! - First working version: the notch opens on hover and shows a grid of metric
  tiles over frosted glass, with an edit mode for rearranging and a handle for
  changing its height. Custom metrics can be authored from any MCP client.

- [`9b16fbd`](https://github.com/haxzie/notch-metrics/commit/9b16fbd5f61e73bad513e373c676e9a658081d3a) Thanks [@haxzie](https://github.com/haxzie)! - Dodo Payments and Lemon Squeezy are live: MRR, revenue and active subscribers
  from both, plus refunds from Lemon Squeezy. Three working revenue connectors
  now instead of one.

- [`2218ec3`](https://github.com/haxzie/notch-metrics/commit/2218ec3d0531a9e88e3c1f289669536a42186223) Thanks [@haxzie](https://github.com/haxzie)! - Widgets is now a browser: search across apps and widgets, open an app to see
  its widgets and connections, then pick a widget, point it at a connection and
  watch a live preview before adding it to the notch. Apps and widgets carry
  search keywords, so "churn" finds churned subscribers and "seo" finds Search
  Console.

- [`99fe84f`](https://github.com/haxzie/notch-metrics/commit/99fe84f47eb378a7665ce83914790e4893c83191) Thanks [@haxzie](https://github.com/haxzie)! - Charts sit at the bottom of a tile, filled with a gradient that fades to
  nothing. Dodo Payments draws in its lime rather than its near-black primary.
  Chart colour, fill and fill opacity are all per-widget configuration now, so a
  new widget sets them rather than patching the app catalogue.

- [`b991256`](https://github.com/haxzie/notch-metrics/commit/b991256486e94fcb8b031412aa1bd0fc56914751) Thanks [@haxzie](https://github.com/haxzie)! - Share a metric as an image. Hovering a tile now shows a share button in its
  top-right corner, which opens a screenshot editor: the card in the middle, and
  a bar underneath with frame size, background and widget size. The preview
  updates as you change them, Download writes a PNG at the frame's real pixel
  size, and Copy puts it on the pasteboard. Backgrounds are eight dark pictures
  plus the brand gradient, and every card is signed with the Notch Metrics mark
  at the bottom.

- [`4cc7608`](https://github.com/haxzie/notch-metrics/commit/4cc7608a857659dbdb52e0ff1039f5ade1aaa671) Thanks [@haxzie](https://github.com/haxzie)! - The share card is one card again: the tile sits straight on the background
  with its own dark surface instead of on a second rounded plate, and it is
  smaller, so the picture around it has room. The signature sits in a tinted
  glass pill, and no longer slides below the crop on backgrounds whose aspect
  ratio overflows the frame.

  Every background is new — twenty wallpapers from the Aurora and Anime sets,
  grouped in the picker — and the editor gains a Chart menu: Line, Bars or
  None, applied to the card only and never written back to the widget.

  The editor's controls float over the card in one pill instead of sitting in
  a toolbar strip. The dropdowns are icon and chevron only, with the caption
  and current value in the tooltip, and the row collapses in two stages as the
  window narrows so Copy and Download are never the controls pushed off the
  end. The window's surface is one dotted, frosted field running the full
  height, behind the title bar included.

- [`cb70e56`](https://github.com/haxzie/notch-metrics/commit/cb70e56c2b3c2eb122311ff7caa13cd2683fda9c) Thanks [@haxzie](https://github.com/haxzie)! - Shopify is connectable, in beta: sales, orders, average order value, refunds,
  new customers, total customers and a feed of recent orders.

  Connect it with a custom app made in your Shopify admin — the store's
  `.myshopify.com` domain and an Admin API access token, with `read_orders` and
  `read_customers`. A token that has only one of the two still connects; the
  widgets it cannot read are greyed out rather than failing later.

  Totals are in the store's own currency rather than converted into the one your
  account prefers, and the tile says so when the two differ. Sales are gross, so
  a refund does not remove the order from the day it was paid — the Refunds
  widget is the other half, and it buckets by the order's date because that is
  the date Shopify gives us. Average order value is the window's own ratio of
  sales to orders, not the average of the daily averages.

  Orders are read in bounded pages, so a store doing more than six hundred
  orders in the window reports a total marked as an undercount rather than
  exhausting Shopify's rate limit mid-walk.

- [`da29bc6`](https://github.com/haxzie/notch-metrics/commit/da29bc64a7c10e81cb479c0ba97faa188389cd37) Thanks [@haxzie](https://github.com/haxzie)! - Added a Connections pane listing every connected account, with rename and
  disconnect, and an Add connection button that goes to Apps. Integrations is
  now called Apps, because it lists what you _can_ connect rather than what you
  have. Every new connection gets a name automatically — "Stripe — Acme Inc" —
  disambiguated when two accounts would otherwise read the same.

- [`43bd57b`](https://github.com/haxzie/notch-metrics/commit/43bd57b0ab6e13ed942bbe53af313e85adb2aa53) Thanks [@haxzie](https://github.com/haxzie)! - The grid is a flow. Widgets run left to right and top to bottom, resizing one
  pushes the rest along to make room, and nothing can be stranded in empty
  space. Header icons are centred on the part of the panel you can actually see.

- [`99fe84f`](https://github.com/haxzie/notch-metrics/commit/99fe84f47eb378a7665ce83914790e4893c83191) Thanks [@haxzie](https://github.com/haxzie)! - Widget numbers sit in the middle of the tile, left aligned, so figures line up
  across tiles of different heights. Every widget now carries its own format —
  k/M/B compaction, the number type, decimals and affixes — chosen when the
  widget is added and overriding what the series reports.

- [`8e5128e`](https://github.com/haxzie/notch-metrics/commit/8e5128e5bbe1e04d5aa7ac4d9b01a043cc030ad3) Thanks [@haxzie](https://github.com/haxzie)! - Use the current Google Analytics and Search Console logos, and swap the Apollo
  connector for GitHub. Search Console's old mark was being shown because
  simple-icons still ships the pre-2021 glyph; Analytics was the right shape but
  flattened to white, which lost the amber that makes it recognisable.

- [`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d) Thanks [@haxzie](https://github.com/haxzie)! - Tiles whose number depends on a time window now carry that window in their
  title, after a middle dot: `Revenue · 30d`, `Visitors · 7d`. Snapshots such as MRR,
  active subscribers or stargazers keep their plain title, since the range would
  not change them. The same rule decides whether the configure pane offers a
  Range control, so the two can no longer disagree. Gallery previews follow it
  too.

- [`d683c69`](https://github.com/haxzie/notch-metrics/commit/d683c69d5dcaea2e441e5f15519dc378b162dc04) Thanks [@haxzie](https://github.com/haxzie)! - The notch fills in much faster when you open it. Metrics for different
  connections are now fetched at the same time rather than one after another, so
  a first load waits for the slowest connection instead of all of them added
  together, and tiles show their last known number straight away while the new
  one is on its way.

  A tile that is still waiting now shows a placeholder shaped like the tile it is
  about to become — a figure-sized bar, and a chart-shaped one underneath when
  the widget draws a chart — instead of telling you to connect an app you have
  already connected. A widget whose account was disconnected, or reconnected
  somewhere else, says "Pick a connection" rather than reporting an error, and
  rebinds itself when there is only one account to pick.

- [`07dc34c`](https://github.com/haxzie/notch-metrics/commit/07dc34cfc2e9209b6a17b4fe5ac5a0d96c7f5f05) Thanks [@haxzie](https://github.com/haxzie)! - YouTube is connectable, in beta: views, watch time, average view duration,
  subscribers, new subscribers, likes and comments for a channel you own.

  Sign-in uses the same Google client as Analytics and Search Console, so there
  is nothing new to authorise beyond the channel's read-only scopes, and the
  hour-long token refreshes in the background. Pick the channel after signing
  in — a brand account's channel is rarely the one the sign-in name suggests.

  Everything time-ranged comes from one YouTube Analytics report, so average
  view duration is watch time over views for the whole window rather than the
  mean of the daily averages. The subscriber total is YouTube's own, which it
  rounds above a thousand; the change against the previous window is the exact
  net gain, so the arrow is right even where the total reads as 12,300. New
  subscribers is gross, so it does not match that change.

### Patch Changes

- [`c1e3544`](https://github.com/haxzie/notch-metrics/commit/c1e3544c5aae12d68123c1633188ac375f73ece5) Thanks [@haxzie](https://github.com/haxzie)! - The Google Analytics and Search Console marks are drawn in their own colours
  again. Silhouetting them in white, as GitHub's mark is, turned the Analytics
  logo into a generic bar chart.

- [`0c9e431`](https://github.com/haxzie/notch-metrics/commit/0c9e43192f405cc49d52ad308019321a8aee4048) Thanks [@haxzie](https://github.com/haxzie)! - Fix sign-in from the Settings window, which opened the browser without its
  PKCE challenge and could only ever show "this link is missing information".

- [`3a81489`](https://github.com/haxzie/notch-metrics/commit/3a814896db7c89bef0d5e521268c7d5a02327c83) Thanks [@haxzie](https://github.com/haxzie)! - Opening the widget gallery now collapses the notch instead of pinning it open; it comes back while a tile is being dragged in and steps aside again after the drop.

- [`eb0a5ed`](https://github.com/haxzie/notch-metrics/commit/eb0a5ed347054c5ab93b9a07aa9e57f992369088) Thanks [@haxzie](https://github.com/haxzie)! - A notch with more than twelve widgets now loads at all. The server caps a
  metrics batch at twelve and rejects the whole body past that, so a thirteenth
  widget made every tile read "Could not reach Notch Metrics". Requests are split
  to fit, and a rejected request, an ended trial and a signed-out app each say so
  instead of blaming the network.

- [`9620015`](https://github.com/haxzie/notch-metrics/commit/9620015231d42e68fa447444b86da8387393c410) Thanks [@haxzie](https://github.com/haxzie)! - Fix the notch after a widget is dragged in from the gallery: the gallery now notices the drop rather than waiting thirty seconds and reappearing on its own, the configure pane the drop opens is no longer closed out from under it, and a collapsed notch never reopens on a stale form instead of the grid.

- [`fbad389`](https://github.com/haxzie/notch-metrics/commit/fbad3892ec5ace996009c182682462a507192176) Thanks [@haxzie](https://github.com/haxzie)! - The account picker in a widget's settings no longer stretches past the pane when the connection has a long name.

- [`05fe0e5`](https://github.com/haxzie/notch-metrics/commit/05fe0e5350b8be22b742248440495ea5d9b788df) Thanks [@haxzie](https://github.com/haxzie)! - The Google Ads and Meta Ads brand marks no longer ship in the app bundle,
  following those connectors being withdrawn. Both keep their name and accent
  in the app catalogue, so a custom metric that names either still reads as
  itself rather than as "Custom" — it draws an SF Symbol now instead of a
  vendored logo, the way Linear already does.

- [`8da36cb`](https://github.com/haxzie/notch-metrics/commit/8da36cb73e8b5824ff45581521802e11a2bd691a) Thanks [@haxzie](https://github.com/haxzie)! - Move refresh and settings to the left of the notch header, beside the app
  name. The right half carries the edit pill, the below-fold count and the
  close button, and on a notched display it begins immediately after the
  camera housing — so the two controls reached for most often sat furthest
  from the pointer.

  Fix the edit-mode well, which was framed larger than the grid and offset
  outwards. Inside a ScrollView that overflows the viewport, so its left and
  right bands were clipped and the dots stopped dead at the outermost tile
  whatever the inset was set to. It is now the background of a padded grid,
  and the padding is the gutter — so the gap around a tile matches the gap
  between two of them.

  Stop the header being squeezed: the panel sized the header band 10pt
  shorter than the band draws itself and counted none of the content's
  padding, so SwiftUI reclaimed the difference from the header's top padding.

  Add a widget gallery. "Add Widget" sits beside Done in edit mode and opens
  a translucent window listing every widget each connector offers, grouped
  the way the server groups them. A widget is dragged from there onto the
  notch, lands where the pointer let go, and opens a configuration window for
  its account, size, number format, chart and range.

  Use the shapes mark for Widgets everywhere it appears.

  Remove the Widgets settings pane. The gallery replaces it end to end —
  browse, drag in, configure — and a second way to add a widget that works
  differently is worse than one. `notchmetrics://settings/widgets` still
  resolves, to Apps.

  Configure widgets inside the notch rather than in a window of their own. A
  split: the tile on the left, its controls on the right, with the grid
  sliding out and the pane sliding in. A second window thrown on screen over
  whatever the user was working in — with its own focus and activation to
  manage — was the wrong shape for changing the thing already on screen.

  Hide the range and chart controls for metrics that cannot use them. A
  snapshot — GitHub's stargazers, forks, open issues — is whatever it is right
  now: there is no series to draw over thirty days and no previous window to
  compare against, so both controls changed nothing.

  Name the connection on a tile, not the app. Somebody with two Stripe
  accounts had two tiles both saying "Stripe". Each widget can be given its own
  name from its configuration, prefilled with the connection's; changing it
  renames that tile only, not the account.

  Refetch a widget when its configuration changes. Switching account or range
  updated the stored widget but left the tile showing the old number until the
  five-minute timer came round.

  Draw bar charts with a solid fill. They used the sparkline's top-down
  falloff, which made a short bar read as a faint one — a second meaning the
  chart does not have.

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

- [`d28ae1e`](https://github.com/haxzie/notch-metrics/commit/d28ae1ea706fd0ee6b732f551e8a77fd615524cd) Thanks [@haxzie](https://github.com/haxzie)! - Polar and PostHog now carry their real marks and colours.

  Polar is monochrome — a white mark on near-black — not the blue it was given,
  which belongs to Polars, the dataframe library at pola.rs. With no brand hue
  to tint a chart line, Polar's graphs are white. PostHog gains its full-colour
  hedgehog on the dark backdrop it is drawn for, keeping its orange for charts.

- [`30ab28e`](https://github.com/haxzie/notch-metrics/commit/30ab28e12368594290b88d04acad59bad52e0609) Thanks [@haxzie](https://github.com/haxzie)! - The resize handle at the bottom of the notch now shows a resize cursor and lights up on hover, and the "+N below" count sits beside it instead of in the header.

- [`d53cb2c`](https://github.com/haxzie/notch-metrics/commit/d53cb2cfc341ce2e9d32b95dd288ffd61f811dd4) Thanks [@haxzie](https://github.com/haxzie)! - Sparkline charts are no longer cut off at the edges of the tile. A peak could
  be drawn flat against the top, troughs sank through the floor, and the dot
  marking the latest value was clipped on the right of every chart — and sliced
  across the top as well whenever the most recent value was also the highest.
  The curve now stays inside the chart, which also means it no longer draws a
  value higher than any the metric actually reported.
