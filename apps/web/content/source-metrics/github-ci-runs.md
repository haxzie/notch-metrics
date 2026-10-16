---
lede: >-
  The ten most recent GitHub Actions runs, newest first, as a feed rather than a count.
---

## A feed, not a number

Unlike every other GitHub widget, this one is a list. The same ten runs
appear whatever window the widget is set to, because what you want from it is
what just happened rather than how many things happened this week.

That is why it carries no sparkline and no comparison against the previous
period. A chart of the last ten runs would be a chart of an arbitrary ten.

## It refreshes faster than everything else

Most metrics in the notch are fetched on a schedule measured in minutes,
because MRR does not change between glances. A CI run does.

This one holds its answer for a minute rather than the quarter of an hour a
daily figure would, because it is the one number here you read in order to
decide whether to go and look at something. Being fifteen minutes behind on a
failing build defeats the point entirely.

## Private repositories

Private repositories work here, alongside public ones.

GitHub has no read-only permission for private repositories on an OAuth app.
The only scope that reaches one is `repo`, and GitHub describes it as full
control. Your consent screen says so.

Notch Metrics only ever reads. It runs no write against your repositories.
Your token is encrypted per connection, and a token copied between accounts
does not decrypt.

If that grant is wider than you want, a
[custom metric](/blog/writing-a-custom-metric) takes a token scoped to one
repository, and that token stays in your own Keychain.

## Picking a repository and a branch

The widget asks which repository, in `owner/name` form, and optionally which
branch. One GitHub connection covers as many repositories as you place
widgets for.

Filtering to a branch is usually what you want on a busy repository.
Unfiltered, ten runs on a project with active pull requests is ten runs from
ten different branches, and your own `main` build is rarely among them.
