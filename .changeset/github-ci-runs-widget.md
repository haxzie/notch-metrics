---
"@notch/integrations": minor
"@notch/mac": minor
---

A GitHub CI widget: point it at a repository and, if you want, one branch, and
it lists the last ten Actions runs newest first, each with its outcome as an
icon — passed, failed, still running, or skipped.

List rows now carry a `state` beside the provider's own `status`, so a tile can
draw an outcome without matching on a provider's vocabulary; a metric can also
declare `freshnessSeconds`, which this one sets to a minute. Without it a CI
feed would inherit the daily bucket's fifteen-minute cache and could report a
build that had since gone red.

Public repositories only, for now: this connection asks GitHub for
`public_repo`, because the read-only alternative for private ones does not
exist for an OAuth app.
