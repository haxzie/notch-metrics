---
"@notch/mac": patch
---

Line the account picker up with the fields above it

A SwiftUI pop-up button does not fill the width it is given: it hugs its title
and centres inside the slot. The 200pt frame that lines the picker up with the
Name field was therefore leaving half the spare width as a gap to its right,
and putting the control's edge somewhere different from every text field in
the pane. Trailing alignment puts it back on the same line.
