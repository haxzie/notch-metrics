# @notch/integrations

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
