---
"@notch/integrations": patch
---

Give PostHog long enough to answer.

Every PostHog number is a HogQL aggregate over the event table rather than a
row read, and a ninety-day one measures five to nine and a half seconds
across this connector's metrics. The eight seconds every provider got was
inside that spread, so the same widget timed out on one refresh and answered
on the next, with nothing about the widget to explain the difference.

A connector can now say how long one of its requests may take. PostHog says
fifteen seconds; nothing else sets it. The whole metric is still bounded by
the twenty-second budget the caller passes in either way, so a slow provider
cannot hold a Worker open.
