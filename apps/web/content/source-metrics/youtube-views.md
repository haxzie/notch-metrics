---
lede: >-
  Views are the count YouTube Analytics reports for the channel over the window, and they are bucketed in Pacific Time whatever your Mac is set to.
---

## The timezone is not yours

YouTube Analytics buckets every daily figure in America/Los_Angeles. A view at
nine in the evening in London lands on the previous Pacific day. If your notch
shows a number that disagrees with your sense of when the spike happened by
one day, this is why, and it is not something the widget can correct without
reporting a figure YouTube would not confirm.

## What counts as a view

A view is a playback that YouTube considers legitimate. Its systems discard
automated and repeated playback before the number reaches the Analytics API,
and that validation lags: a figure for the last day or two can settle
downwards after the fact. Treat the most recent bucket as provisional.

Views do not distinguish between a viewer who watched three seconds and one
who watched the whole thing. Put watch time or average view duration beside
this widget and you can tell those two apart.
