---
"@notch/integrations": minor
---

Plausible and Amplitude are connectable, in beta.

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
