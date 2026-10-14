---
"@notch/mac": patch
---

"Mark all read" in the notification centre now actually marks the rows read.
The inbox held read state alongside the notifications rather than on them, and
every row, badge and bold title reads it off the notification itself, so the
button changed only the count in the sidebar and left the list looking
untouched. Marking one connection read also told the server to clear the whole
inbox, which another Mac would then agree with.
