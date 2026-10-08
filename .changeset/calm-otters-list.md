---
"@notch/integrations": minor
"@notch/schemas": minor
"@notch/mac": minor
---

Polar and Paddle are now live connectors, and every payment provider gains a
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
