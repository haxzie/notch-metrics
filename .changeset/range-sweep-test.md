---
"@notch/integrations": patch
---

Adds a sweep that puts every metric through every range its own manifest
offers, so a connector that advertises a window it cannot serve fails its
own test rather than a user's tile.
