---
"@notch/integrations": patch
---

Answer a Google Analytics widget over 90 days and 12 months.

Google sends an empty object for a date range it found no data at all in, so
the entry in `totals` has no range name on it and no figure in it. Every
window has one behind it to compare against, and on a property younger than
that window — a site set up three months ago, asked for the year — the range
Google empties is always the comparison one. Reading the range name off that
empty entry threw, and the tile said the provider could not be reached for a
report that had arrived intact.

An empty entry is now read as the zero it is, matched to its range by
position. A 90-day and a 12-month tile answer, with no percentage beside them
until there is a window to compare against.
