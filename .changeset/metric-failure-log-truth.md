---
"@notch/mac": patch
---

Say the right bucket, and how long a rate limit lasts, when a widget fails.

Two copies of the one log line that explains a failing tile, and they had
drifted. The batch's printed the widget's stored `granularity` — frozen when
the widget is created, changed by no control since — while every request is
built from the range instead. So a 30-day tile that asked the server for
daily buckets was logged as having asked for hourly ones, which is the exact
signature of a bug fixed long ago somewhere else entirely. A log that names a
dead bug at the moment something is going wrong is worse than no log.

The line now also carries `retryAfterSeconds` when the server sends it. It is
the only number that says how long a rate limit has left, because a
provider's own `Retry-After` is obeyed literally rather than fed into a curve
of our own — and without it a limit that clears in a minute and a spend cap
that will never clear on its own read identically.

One copy now, so the next edit cannot land on half of them.
