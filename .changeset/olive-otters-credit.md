---
"@notch/mac": patch
---

Give the share card real glass, the provider's name, and one size.

Four changes to the same picture.

The plates were flat black rectangles. `.ultraThinMaterial` is what the
notch uses, but a material samples the window behind it and `ImageRenderer`
declines to draw one at all, so the exported card never had frost in it —
only a tint. The card now draws the background twice, blurs the second copy
and masks it to the plates, which is the same effect built out of things the
renderer does draw. The tint over it went from 55% to 62% black, so a pale
wallpaper cannot wash the figure out.

The footer pill credits the provider first, then a hairline, then Notch
Metrics. A card posted on its own said where the screenshot was made but not
what it was of.

The size menu is gone and every card is a 2x2. A share card holds one tile
with nothing to pack around it, so the span is a composition decision rather
than the user's: a 1x1 came out a stamp in the middle of a 1080px square and
a 6x2 left a letterbox of wallpaper above and below it.

The background menu is a four-column grid in a popover. A menu row is one
line of text and one 18pt image, which is as much of a picture as AppKit
will put in front of a choice — and the choice here is the picture. The Haze
set joins Aurora and Anime, two of which left.
