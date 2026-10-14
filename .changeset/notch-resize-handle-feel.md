---
"@notch/mac": patch
---

Steadier resize handle: the pointer turns into a resize cursor the first time
it reaches the handle rather than the second, the panel's bottom edge no longer
eases and snaps on two clocks while the handle is held, and letting go settles
onto the row instead of jumping to it.

The "+3 below" label is now a button — a chevron centred just above the handle
that scrolls down a screenful, and hides once the last widget is in view.
