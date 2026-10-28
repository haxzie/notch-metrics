---
"@notch/mac": patch
---

Money with cents now reads as money: $428.60 rather than $428.6. The minimum
fraction digits were zero, so an amount whose cents ended in a zero lost one of
its two decimal places.

A metric's own format is also honoured where the widget has not overridden it,
which is what makes Search Console's average position read 8.4 rather than
rounding to the integer a rank is never quoted as.
