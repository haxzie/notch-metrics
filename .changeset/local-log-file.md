---
"@notch/mac": minor
---

The app now keeps a log on disk at
`~/Library/Application Support/NotchMetrics/logs/app-<date>.log`: every
request with its status and timing, every failed widget with the server's
own reason, and the build and server it started against. Five days are
kept. Anything shaped like a token or a key is blanked before it is
written.

A tile that fails on one range and not another, or only on one person's
account, previously left nothing behind to look at — the unified log needs
Console.app and cannot be handed to anybody.

Switching a widget's range also no longer leaves the previous range's number
on screen when the new one fails. The last good figure is still held through
a provider blip, but only while it answers the same question; a 30-day total
under a title reading "7d" is worse than the error it was standing in for.
