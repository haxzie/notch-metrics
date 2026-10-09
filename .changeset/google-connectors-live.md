---
"@notch/integrations": minor
---

Google Analytics and Google Search Console are now connectable, in beta.

Analytics reads active users, new users, sessions and page views from a GA4
property chosen after signing in; the headline for users is Google's own
de-duplicated count over the window. Search Console reads clicks, impressions,
click-through rate and average position for a chosen property, with rates and
positions computed from the summed components rather than averaged by day.
Both connectors use the server's Google client, refresh their hour-long tokens
in the background, and ask for read-only scopes only.
