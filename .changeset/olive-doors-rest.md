---
"@notch/mac": patch
---

Move refresh and settings to the left of the notch header, beside the app
name. The right half carries the edit pill, the below-fold count and the
close button, and on a notched display it begins immediately after the
camera housing — so the two controls reached for most often sat furthest
from the pointer.

Give the edit-mode well its own margin from the panel edges, and stop the
header being squeezed. The panel sized the header band 10pt shorter than
the band draws itself and counted none of the content's padding, so the
VStack was over-committed and SwiftUI reclaimed the difference from the
header's top padding — the controls slid up against the top edge. Both
numbers now come from one expression.

Use the shapes mark for Widgets everywhere it appears: the notch's edit
button and the settings sidebar.
