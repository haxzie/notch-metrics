---
"@notch/mac": minor
"@notch/schemas": patch
---

Notch Metrics updates itself. The Updates pane checks the release feed, offers
the version it finds, downloads it, checks it and swaps the app over, and a
coloured chip in the bottom corner of the notch says so without anybody going
looking in Settings.

The installing half already existed. What is new is everything that decides
whether to install anything: a six-hourly poll, the build-number comparison,
the download with a progress bar, and the states the pane draws. A build this
Mac cannot run reads as up to date rather than as a failure, a half-written
download is thrown away rather than offered, and a verified one survives a
relaunch so quitting mid-update does not mean fetching it again.

The feed is the Worker's, with the bucket as a fallback for the case the Worker
is down. A 404 from the Worker is treated as an answer rather than as a reason
to read the bucket, which is what keeps `PINNED_VERSION` able to pull a bad
release back.
