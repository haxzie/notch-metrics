---
"@notch/integrations": minor
---

PostHog is connectable: active users, new users, events, pageviews and
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
