---
lede: >-
  A fork count is the number of copies of the repository on other accounts, and it moves for different reasons than stars do.
---

## Forks are contributors and vendorers, mixed together

Every pull request from outside the organisation starts with a fork, so a
healthy contribution flow pushes this number up. So does every person who
copied the project to change one line for themselves and never came back.
The two are indistinguishable in the count.

That makes the ratio more useful than the figure. A project with many stars
and few forks is being watched. One with forks approaching a tenth of its
stars is being used and modified.

## What GitHub returns

The repository object carries `forks_count`, which counts direct forks only.
A fork of a fork belongs to its own parent and is not added here. The number
also never goes down when somebody deletes their copy in the same session,
because GitHub recomputes it on its own schedule.

The widget asks which repository to count. Add a second widget for a second
repository.
