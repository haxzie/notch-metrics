---
"@notch/mac": patch
---

Fill in a widget added while the notch was already fetching.

A tile dropped in from the browser sometimes previewed nothing at all — a
skeleton beside a configure pane with the account picked and every setting
right — and stayed that way for up to five minutes before a number appeared.

Nothing serialised `refresh()`. It is called from the five-minute poll, the
refresh button, connection adoption and the browser the instant a tile lands,
and the batch behind it takes four to ten seconds, so two or three ran at
once as a matter of course. Each one copied the whole `states` dictionary
before its request and assigned the copy back after, which is a
last-writer-wins overwrite of every tile including the ones it never asked
about. A widget added while a batch was in flight did not exist when that
copy was taken, so the commit _removed_ its entry — and a tile with no entry
renders as loading.

Two changes. `refresh()` now runs one batch at a time with at most one caller
queued behind it, chained rather than joined: a caller that attached itself
to the request already in flight would be answered about a notch that did
not contain its own widget. And the results are merged per widget rather than
assigned, under three conditions — only the widgets that run asked about, only
where nothing newer has answered since, and only while the widget is still
asking the question that was sent. The last of those also retires a quieter
bug, where a slow batch could paint a stale figure under a range the user had
already moved on from.

`refreshOne` answers a single picker change in well under a second and was
the most frequent loser of the race it is meant to win.
