---
"@notch/integrations": minor
"@notch/schemas": minor
"@notch/mac": minor
---

Add a RevenueCat connector with six widgets: MRR, revenue over the window with
a comparison to the window before, active subscriptions, active trials, and
RevenueCat's 28-day new and active customer counts.

Connect it with a v2 secret API key that has Charts & Metrics read. A key that
can also list projects is named after the project; one that cannot works too,
provided the project ID is typed in. A key that can see several projects is
asked to pick one rather than having one chosen for it.

Figures come from RevenueCat's own Overview and revenue endpoints, so they match
the dashboard. Money arrives as decimals and is converted to minor units per
currency, so a yen figure is not multiplied by a hundred.
