---
lede: >-
  Open pull requests are work waiting on a review, which makes this the clearest single measure of whether a project is blocked on its maintainers.
---

## What is counted

Pull requests in the open state, through the search API with
`is:pr is:open`. Drafts are included: a draft is open and it is work in
progress, and excluding it would understate what is actually in flight.
Closed and merged pull requests are not counted, whichever way they ended.

## Reading it next to open issues

The two GitHub backlog numbers say different things. Open issues are work
nobody has started. Open pull requests are work somebody has finished and
nobody has looked at. A project where issues are flat and pull requests climb
has a review bottleneck, and that is the one that loses contributors.

The widget asks which repository to count, so a maintainer with four
repositories places four widgets and sees which one is holding people up.
