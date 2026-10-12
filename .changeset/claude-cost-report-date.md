---
"@notch/integrations": patch
---

Fix connecting Claude, which failed with "api.anthropic.com returned 400"
however good the admin key was.

The cost report snaps `starting_at` up to the next UTC day and defaults
`ending_at` to the start of today, so the `now - 24h` the connect check used
snapped to exactly that default and the range was empty. Anthropic refuses
that with "ending date must be after starting date" — a 400 that reads as a
rejected credential. Outside the midnight UTC hour it failed every time, so
the connector could not be connected at all. The window is now a whole day,
and the spend query floors to the day as well rather than letting the snap
drop the first one.

A provider's own explanation is also no longer thrown away. A 4xx that is not
401, 403 or 429 now carries the message the provider sent, so the next bad
parameter names itself instead of showing a bare status.

And a refused cost report no longer takes the connection down with it. Cost
is a separate permission from usage on both providers, so a key that reads
tokens but not dollars connects with spend greyed out — that was the intent,
but only an explicit 403 took the narrow path, and any other failure was
fatal to a connection whose other metrics all worked.
