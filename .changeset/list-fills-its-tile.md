---
"@notch/mac": patch
---

A list widget fills its tile.

The number of rows was a formula that came out at five for every 2x2 tile
whatever its real height, while the server sends ten. Half the rows were
thrown away and the space they would have filled was left empty. The tile
now fits as many whole rows as it has room for.
