---
"@notch/mac": patch
---

Find the resize handle on the way in, not after you have passed it.

The handle's target sat entirely inside the panel, so a pointer coming up at
the notch from the screen below had to cross the bottom edge before the cursor
changed, and the handle read as inert from the one direction people approach
it. It now reaches a little past the edge, and the whole band is hittable when
an update chip is sharing it.
