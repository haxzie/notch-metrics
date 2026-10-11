# @notch/schemas

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
