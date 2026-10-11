---
lede: >-
  Stars are GitHub's bookmark, and for an open-source project they are the closest thing to a public growth chart.
---

## What a star actually counts

A star is one account marking the repository. It is not a download, not a
fork and not a user. A project with ten thousand stars may have a hundred
people running it, and a tool with four hundred stars may be in production at
every one of those four hundred companies. Read it as attention, not adoption.

GitHub returns the current total on the repository object as
`stargazers_count`. There is no endpoint for the total on an arbitrary past
day: the starring events exist, but reconstructing a history means paging
through every one of them with a preview media type, which is why most star
history charts are built by a service that has been recording the number
daily since before you needed it.

## Why the widget has no sparkline

Notch Metrics reports the count GitHub returns right now. Asking for a
sparkline would mean paging the full stargazer history on every refresh, and
the rate limit makes that a bad trade for a number that moves slowly.

The widget asks which repository to count, in `owner/name` form, because one
GitHub connection usually covers several. Add a second widget for a second
repository.
