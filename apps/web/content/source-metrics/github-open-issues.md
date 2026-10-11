---
lede: >-
  Open issues are the backlog, counted properly. GitHub's own `open_issues_count` includes pull requests, and this one does not.
---

## Why the obvious field is the wrong field

In GitHub's data model a pull request is an issue. The repository object's
`open_issues_count` therefore adds your open pull requests to your open
issues, and a repository with an active contribution flow reads as though its
backlog has doubled overnight.

Notch Metrics counts issues through the search API with `is:issue is:open`,
which excludes pull requests by type rather than by filtering them out
afterwards. The number in your notch is the backlog you would see on the
Issues tab.

## Reading it

A figure that climbs steadily is triage falling behind, not necessarily
quality falling. A figure that drops in one step is usually a bulk close, so
check before celebrating. Pair it with the open pull requests widget and the
two together say whether the project is blocked on maintainers or on
contributors.

The widget asks which repository to count.
