---
"@notch/integrations": minor
"@notch/mac": minor
---

Shopify is connectable, in beta: sales, orders, average order value, refunds,
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
