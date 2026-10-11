---
lede: >-
  Likes are the count over the window, and they are the cheapest engagement signal a viewer can give.
---

## Gross, over the window

The Analytics API returns likes added in the window, bucketed by Pacific day.
It is a gross figure: a viewer who likes a video and later removes the like
is counted here and the removal is reported separately as a dislike event
rather than being netted off.

## What it is useful for

Likes track how a video landed, faster than watch time does and far faster
than subscribers. A video with normal views and unusually high likes has hit
something, and that is the signal worth acting on while it is still fresh.

The useful form is a ratio. Likes divided by views over the same window
normalises for reach, so put the views widget beside this one. A ratio that
drops while views climb means a video found a bigger audience that cared less.
