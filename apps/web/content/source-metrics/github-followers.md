---
lede: >-
  Followers are the count on the account itself, not on any repository, so this is the one GitHub widget that needs no repository.
---

## Account followers, not repository watchers

GitHub has three numbers people confuse. Stars bookmark a repository.
Watchers subscribe to a repository's notifications. Followers subscribe to an
account's public activity, and that is what this number is.

For an organisation, followers are people tracking everything the
organisation publishes. For a personal account they are closer to a social
graph: people who want your new repositories in their feed.

## Why there is no sparkline

GitHub returns the current total on the user object as `followers`. There is
no endpoint for the count on a past date and no event stream to reconstruct
one from, so the widget shows the figure as it stands. That is also why this
is the only GitHub metric with no repository to pick: it belongs to the
account the connection authorised, not to any project under it.
