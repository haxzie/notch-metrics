---
"@notch/mac": patch
---

Changing a widget's settings now visibly refetches it. The tile drops to its
loading skeleton — or to the last number it has for the range you picked —
instead of leaving the previous window's figure sitting there, and the
request for the settings you just moved off is cancelled rather than left to
land on top of the new one. Rapid changes coalesce into one fetch instead of
one per keystroke.
