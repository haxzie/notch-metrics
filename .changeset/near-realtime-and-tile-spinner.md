---
"@notch/mac": minor
"@notch/integrations": minor
---

Refresh the numbers that can actually move, and say when you are

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
