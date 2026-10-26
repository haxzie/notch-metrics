# @notch/integrations

## 0.4.0

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

### Patch Changes

- [`c07f19c`](https://github.com/haxzie/notch-metrics/commit/c07f19c55c09f07ada2a8fd4201d3b77e18e789f) Thanks [@haxzie](https://github.com/haxzie)! - Google Analytics, Search Console and YouTube are out of beta.

  Google has verified the OAuth client the three of them share, so the consent
  screen they lead into is no longer the one warning people the app is
  unverified, and the hundred-test-user cap on who can reach it is gone.

  Nothing about the connectors themselves changed, and nothing in the app was
  gated on the verification: the scopes are the ones they always asked for, and
  all three have been connectable since they shipped. What moves is the badge
  on their source pages and their rank in the registry, both of which said
  "beta" on connectors whose edges are no longer being worked on.

  The Limited Use disclosure on the connect page stays exactly where it is.
  Google's API Services User Data Policy requires it on the screen leading into
  consent whether or not the client is verified, and it is the kind of thing an
  approval is withdrawn over.

- [`c86cc4c`](https://github.com/haxzie/notch-metrics/commit/c86cc4c9264b9fa90be0346ef7b555f2946eab3f) Thanks [@haxzie](https://github.com/haxzie)! - Metrics are defined per metric, by a factory, instead of as a manifest entry
  and a far-away `case`.

  A widget was three edits in one file that nothing connected: a descriptor in
  `manifest.metrics`, its id in `verify`'s hand-written `availableMetrics`, and
  a `case` in a `fetchMetric` switch some five hundred lines below. That split
  is why a `granularities` promising a bucket the `case` throws on was invisible
  until it reached a tile, and why a metric added without being copied into the
  array was simply unreachable.

  `scalarMetric`, `seriesMetric` and `listMetric` take a descriptor and its
  `fetch` together, and `provider()` derives all three of those from the list it
  is given. One factory per shape rather than one `metric({ shape })`, because
  the discriminant has to be in the function name for inference to run forwards
  — otherwise a mistake inside `fetch` reports as "no overload matches this
  call" against line one of a forty-line literal.

  Shape replaces the two booleans internally. `supportsSeries: false` and
  `supportsCompare: false` described both GitHub's stars and its CI feed for
  entirely unrelated reasons — one has no history, the other is a feed with no
  window — and nothing in the pair said which. It also puts `granularities` on
  the two arms where anything reads it: on a snapshot it was decoration that
  looked load-bearing, which is how both LLM connectors came to offer a range
  they cannot answer.

  All nineteen providers are converted, and the shared payments feed with them:
  `recentPaymentsMetric` replaces a descriptor spread into six manifests and a
  builder called from six `case` arms, with a `totalIn` hook for the one
  provider — Shopify — whose feed totals in the store's currency rather than the
  user's.

  Nothing crosses the wire differently. The catalogue still carries
  `supportsSeries`, `supportsCompare` and `granularities`, derived, so installed
  apps are unaffected, no app release is involved and no contract is
  regenerated.

  Converting turned up a fourth shape I had not expected. `total` is a number
  _for_ a window, with a delta and no breakdown: RevenueCat's revenue comes from
  an endpoint that answers one figure per call, so a thirty-point sparkline
  would be a minute of its rate budget, and YouTube's subscriber count has a
  running total from one API and daily deltas from another with no way to join
  them into a line. Both are the `supportsSeries: false, supportsCompare: true`
  pair, which the first draft of this change assumed was nonsense and would have
  flattened into a plain snapshot — losing a working comparison on two metrics.

  Two things this now catches that nothing did. A provider declaring one metric
  id twice throws at module load rather than silently dropping one and leaving
  two browser rows sharing an `Identifiable` id. And a `fetch` returning the
  wrong thing for its shape is a compile error, instead of a snapshot
  hand-rolling `points` and inventing a flat line.

  Three side tables keyed on metric id are gone with the switches that read
  them: PostHog's `SPECS`, Amplitude's `SPECS`, YouTube's `figure`/`UNITS`/
  `SERVED` trio, and the `METRICS` lookups in Plausible and Google Analytics.
  Each had to agree with its manifest, and several quietly did not.

  The only descriptor change on the wire is `granularities` on a metric with no
  window, which now reads as every bucket. Nothing interprets it once
  `supportsSeries` is false, and installed apps run `clampRange()` whether the
  Range row is shown or not — so a narrow list there would silently rewrite the
  stored range of a snapshot widget the first time its pane opened.

- Updated dependencies [[`95bf1a7`](https://github.com/haxzie/notch-metrics/commit/95bf1a7203615230bfdba95c12eee31eb224ea83), [`8ff2372`](https://github.com/haxzie/notch-metrics/commit/8ff23725db81c1df93dc7275a1dbcd4c2f1354b6)]:
  - @notch/schemas@0.3.0

## 0.3.0

### Minor Changes

- [`1becc46`](https://github.com/haxzie/notch-metrics/commit/1becc460c6350b16764bef88616c5f1ab429a723) Thanks [@haxzie](https://github.com/haxzie)! - Read private repositories on a GitHub connection.

  GitHub has no read-only scope for private repositories on an OAuth app. The
  only scope that reaches one is `repo`, which carries read and write on code
  for every repository the signed-in account can see. That is the grant now
  asked for, and the connect page says so in those terms rather than in terms
  of what the connector uses.

  A connection made before this keeps working for public repositories. GitHub
  returns the scopes it granted on every response, so a private repository on
  an older connection now says to reconnect instead of leaving a correct
  repository name looking wrong.

### Patch Changes

- [`4ca8331`](https://github.com/haxzie/notch-metrics/commit/4ca83318fdc0f389e85d4a5c7756d9ebe22ce077) Thanks [@haxzie](https://github.com/haxzie)! - Answer a Google Analytics widget over 90 days and 12 months.

  Google sends an empty object for a date range it found no data at all in, so
  the entry in `totals` has no range name on it and no figure in it. Every
  window has one behind it to compare against, and on a property younger than
  that window — a site set up three months ago, asked for the year — the range
  Google empties is always the comparison one. Reading the range name off that
  empty entry threw, and the tile said the provider could not be reached for a
  report that had arrived intact.

  An empty entry is now read as the zero it is, matched to its range by
  position. A 90-day and a 12-month tile answer, with no percentage beside them
  until there is a window to compare against.

- [`0a7fc50`](https://github.com/haxzie/notch-metrics/commit/0a7fc50250b9f100e9b1958eb2a58d3919014217) Thanks [@haxzie](https://github.com/haxzie)! - Stop a single rejected request from marking a whole connection broken.

  A GitHub repository that has been renamed, mistyped or made private answers
  404, and that was being reported as an authentication failure — which marked
  the connection dead, asked for a reconnect that could not fix a repository
  name, and stopped the connection's token being refreshed from then on. It is
  now reported against the widget's repository, where the problem actually is.

  Google's connectors had the same shape of fault from the other direction.
  YouTube, Search Console and Analytics all answer 403 when a daily quota is
  spent, and that was being read as a rejected credential rather than as a wait.
  A spent quota is now a rate limit, and clears on its own.

- [`26463a2`](https://github.com/haxzie/notch-metrics/commit/26463a22a8899ef477ebf6b761cc2e1d6871e02d) Thanks [@haxzie](https://github.com/haxzie)! - Give PostHog long enough to answer.

  Every PostHog number is a HogQL aggregate over the event table rather than a
  row read, and a ninety-day one measures five to nine and a half seconds
  across this connector's metrics. The eight seconds every provider got was
  inside that spread, so the same widget timed out on one refresh and answered
  on the next, with nothing about the widget to explain the difference.

  A connector can now say how long one of its requests may take. PostHog says
  fifteen seconds; nothing else sets it. The whole metric is still bounded by
  the twenty-second budget the caller passes in either way, so a slow provider
  cannot hold a Worker open.

## 0.2.0

### Minor Changes

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

- [`6e4cb6e`](https://github.com/haxzie/notch-metrics/commit/6e4cb6e7e2340e4725022d5b277cd862b50ad062) Thanks [@haxzie](https://github.com/haxzie)! - Fix connecting Claude, which failed with "api.anthropic.com returned 400"
  however good the admin key was.

  The cost report snaps `starting_at` up to the next UTC day and defaults
  `ending_at` to the start of today, so the `now - 24h` the connect check used
  snapped to exactly that default and the range was empty. Anthropic refuses
  that with "ending date must be after starting date" — a 400 that reads as a
  rejected credential. Outside the midnight UTC hour it failed every time, so
  the connector could not be connected at all. The window is now a whole day,
  and the spend query floors to the day as well rather than letting the snap
  drop the first one.

  A provider's own explanation is also no longer thrown away. A 4xx that is not
  401, 403 or 429 now carries the message the provider sent, so the next bad
  parameter names itself instead of showing a bare status.

  And a refused cost report no longer takes the connection down with it. Cost
  is a separate permission from usage on both providers, so a key that reads
  tokens but not dollars connects with spend greyed out — that was the intent,
  but only an explicit 403 took the narrow path, and any other failure was
  fatal to a connection whose other metrics all worked.

- [`33d152b`](https://github.com/haxzie/notch-metrics/commit/33d152b03528eefe0cb9e4a9868817b427b859c2) Thanks [@haxzie](https://github.com/haxzie)! - Reword the connector taglines and metric methodology strings without em
  dashes, so they read correctly on the new public source pages as well as in
  the app's tooltips.

- [`5f27d66`](https://github.com/haxzie/notch-metrics/commit/5f27d66618798e78c35978dac6f7892da501a12c) Thanks [@haxzie](https://github.com/haxzie)! - Adds a sweep that puts every metric through every range its own manifest
  offers, so a connector that advertises a window it cannot serve fails its
  own test rather than a user's tile.
- Updated dependencies [[`f98d0a9`](https://github.com/haxzie/notch-metrics/commit/f98d0a9e4ed812288a2353f9c4a9ed3ce894ce16), [`ad1b0ff`](https://github.com/haxzie/notch-metrics/commit/ad1b0ff02da8e761104919882b2fabe87898997f), [`eca363b`](https://github.com/haxzie/notch-metrics/commit/eca363ba62ade87c90157c57d50d66dcee447a2d)]:
  - @notch/schemas@0.2.0

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

- [`05fe0e5`](https://github.com/haxzie/notch-metrics/commit/05fe0e5350b8be22b742248440495ea5d9b788df) Thanks [@haxzie](https://github.com/haxzie)! - The Google Ads and Meta Ads connectors are withdrawn.

  Both were declared but never implemented, and both were the expensive kind of
  unimplemented: a Marketing API app each, submitted for review, plus a Google
  Ads developer token, before a single number could be read. The catalogue no
  longer lists them, `ad_spend` and `ad_conversions` leave the metric
  vocabulary with nothing left to produce them, and the website's connector
  wall and its Marketing layout no longer advertise either.

  Nothing a user has can break: a connector that never shipped has no
  integration rows and no widgets pointing at it. A custom metric can still name
  Google Ads or Meta Ads as the app its number came from — that catalogue is
  deliberately a superset of the connectors, and both keep their name and accent
  there alongside Linear.

- [`b3ebc2c`](https://github.com/haxzie/notch-metrics/commit/b3ebc2c5e7770f2c8cc3d0386c290c542f13b693) Thanks [@haxzie](https://github.com/haxzie)! - Google Analytics and Google Search Console are now connectable, in beta.

  Analytics reads active users, new users, sessions and page views from a GA4
  property chosen after signing in; the headline for users is Google's own
  de-duplicated count over the window. Search Console reads clicks, impressions,
  click-through rate and average position for a chosen property, with rates and
  positions computed from the summed components rather than averaged by day.
  Both connectors use the server's Google client, refresh their hour-long tokens
  in the background, and ask for read-only scopes only.

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

- [`ba77bfd`](https://github.com/haxzie/notch-metrics/commit/ba77bfd68396ff96e4b0f7972a16cce8e24036b8) Thanks [@haxzie](https://github.com/haxzie)! - Plausible and Amplitude are connectable, in beta.

  Plausible reads unique visitors, pageviews, sessions and bounce rate for one
  site, with a Stats API key. Each chart is bucketed by Plausible itself at the
  granularity the widget asks for, so a week's bounce rate is weighted by that
  week's sessions rather than being the mean of seven daily rates, and every
  headline is Plausible's own aggregate for the window — the figure its
  dashboard shows — rather than the sum of the bars, which for unique visitors
  would count one person once per day they visited.

  Amplitude reads active users, new users and events from a project's key pair.
  Active users take their headline from Amplitude's own de-duplicated figure for
  the whole window. Days are asked for one at a time and rolled up here, so a
  week in the notch starts on the same day as every other tile's.

  Both connectors say which region they are for, because a US key presented to
  the EU host is rejected exactly the way a revoked key is, and name the account
  or site so a second connection is told apart from the first.

- [`d7b85bc`](https://github.com/haxzie/notch-metrics/commit/d7b85bca1369428fc882153c7900b17c20ccfa2f) Thanks [@haxzie](https://github.com/haxzie)! - PostHog is connectable: active users, new users, events, pageviews and
  sessions.

  Each metric is one bounded HogQL aggregate against the project's own data, so
  the figures are PostHog's and the chart is drawn in its project timezone —
  what its dashboards show. Active users and sessions take their headline from a
  de-duplicated window total rather than the sum of their own bars, because one
  person active on three days is three bars and one user. The project ID is
  optional; left blank, the key's current project is used.

  Connectors in beta — PostHog, Google Analytics and Search Console — are no
  longer shown as "Soon" on the website. They have been connectable for as long
  as they have been beta, and the site was the only thing saying otherwise.

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

- [`d5c8e46`](https://github.com/haxzie/notch-metrics/commit/d5c8e46f32b5487f34392faa20e912799165f8d8) Thanks [@haxzie](https://github.com/haxzie)! - OAuth connections refresh themselves before their tokens expire. Each
  connector declares how early and how often, and the Worker's cron rotates any
  token inside that window; a request that arrives first does the same. GitHub
  connections made with an OAuth App that issues expiring tokens no longer need
  reconnecting every eight hours.

- [`24ed7d0`](https://github.com/haxzie/notch-metrics/commit/24ed7d00e2801af2f6a0c7cea9a24c135613ba3e) Thanks [@haxzie](https://github.com/haxzie)! - Implement the GitHub connector: stars, forks, open issues and open pull
  requests from one repository, connected over OAuth.

  It is the first connector to use the OAuth leg of the connect flow, which was
  scaffolded but had no consumers — authorize, callback, and a post-grant
  selection step, with the access token held under the same envelope encryption
  a finished integration uses while the user picks a repository.

  Open issues are counted through search rather than taken from the repository
  object's `open_issues_count`, which includes pull requests and therefore reads
  high by exactly the number of open PRs.

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

- [`ade7ca9`](https://github.com/haxzie/notch-metrics/commit/ade7ca95910cb6f1120701ea5dbf8e4bb640f1be) Thanks [@haxzie](https://github.com/haxzie)! - YouTube now reports estimated revenue, ad revenue and RPM for monetised
  channels.

  Sign-in asks for YouTube Analytics' monetary scope, which is a superset of
  the plain one rather than a second scope beside it — Google's own wording is
  "monetary and non-monetary". YouTube does the currency conversion, because it
  converts each day at that day's rate and converting a whole window at today's
  rate is a different number from the one Studio shows. A currency YouTube
  cannot pay out in falls back to US dollars and the tile says so.

  Most channels are not in the YouTube Partner Program, and YouTube answers 403
  to any report that so much as names a revenue column. So revenue is asked for
  in its own request, leaving view counts working for everybody, and connecting
  a channel without revenue succeeds with a shorter list of metrics rather than
  failing. Existing connections authorised before this keep working and simply
  show no revenue until they are reconnected.

  RPM is revenue over views across the whole window, the way Studio computes
  it, not the average of the daily rates — and not CPM, which counts only
  monetised playbacks. Revenue is rounded to the cent once per window rather
  than once per day, and is provisional until YouTube's month-end adjustment,
  which the tile also says.

### Patch Changes

- [`8312a03`](https://github.com/haxzie/notch-metrics/commit/8312a0360df771e200c5ca49893e8949df20a5d2) Thanks [@haxzie](https://github.com/haxzie)! - Every connector manifest's `iconPath` now points at a URL that exists.

  All eighteen said `/providers/<id>.svg`; the website has only ever served
  `/connectors/<id>.svg`, and the assets host named in the field's own
  description serves neither — it mirrors releases. Nothing rendered from the
  field, because both clients resolve a mark from the connector id instead, so
  nothing noticed. A test now pins the value, since a field nothing reads is a
  field nothing notices has gone stale.

- [`d28ae1e`](https://github.com/haxzie/notch-metrics/commit/d28ae1ea706fd0ee6b732f551e8a77fd615524cd) Thanks [@haxzie](https://github.com/haxzie)! - Polar and PostHog now carry their real marks and colours.

  Polar is monochrome — a white mark on near-black — not the blue it was given,
  which belongs to Polars, the dataframe library at pola.rs. With no brand hue
  to tint a chart line, Polar's graphs are white. PostHog gains its full-colour
  hedgehog on the dark backdrop it is drawn for, keeping its orange for charts.

- Updated dependencies [[`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d), [`c73f92c`](https://github.com/haxzie/notch-metrics/commit/c73f92c8ca4340352ea07e5ae16072e61680cd6d), [`b523d18`](https://github.com/haxzie/notch-metrics/commit/b523d1855426528177e84307ebb8b6b2fed86c03), [`a8188dc`](https://github.com/haxzie/notch-metrics/commit/a8188dcf86262d3c8e0e494bd60e40c285cb49bf)]:
  - @notch/schemas@0.1.0
