---
"@notch/mac": minor
---

The notch fills in much faster when you open it. Metrics for different
connections are now fetched at the same time rather than one after another, so
a first load waits for the slowest connection instead of all of them added
together, and tiles show their last known number straight away while the new
one is on its way.

A tile that is still waiting now shows a placeholder shaped like the tile it is
about to become — a figure-sized bar, and a chart-shaped one underneath when
the widget draws a chart — instead of telling you to connect an app you have
already connected. A widget whose account was disconnected, or reconnected
somewhere else, says "Pick a connection" rather than reporting an error, and
rebinds itself when there is only one account to pick.
