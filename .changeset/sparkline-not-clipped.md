---
"@notch/mac": patch
---

Sparkline charts are no longer cut off at the edges of the tile. A peak could
be drawn flat against the top, troughs sank through the floor, and the dot
marking the latest value was clipped on the right of every chart — and sliced
across the top as well whenever the most recent value was also the highest.
The curve now stays inside the chart, which also means it no longer draws a
value higher than any the metric actually reported.
