---
"@notch/mac": patch
---

The range picker now offers only the ranges a metric can actually answer
for. Every connector has declared which buckets its metrics support since
the first one shipped, and nothing read it — all five ranges were offered
for everything, so picking one the metric could not serve came back as an
error on the tile. On the AI connectors that was "12m" on any metric and
"24h" on spend, which both report once a day. A widget already saved on a
range its metric cannot serve is moved to the nearest one that works when
its settings are opened.

Changing a setting no longer resets the widget's size. The configure pane
held a copy of the widget taken when it opened and wrote the whole copy back
on every edit, so resizing a tile with the pane still open and then touching
any control sprang it back to the size it had been.
