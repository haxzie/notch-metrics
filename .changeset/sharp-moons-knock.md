---
"@notch/mac": patch
---

A click on a tile opens the number where it lives the first time, not the
second. The notch deliberately never takes focus, so that brushing it does not
pull you out of what you are typing in. The cost was that the first click
arriving from another app was spent taking focus and never reached the tile
under the pointer.
