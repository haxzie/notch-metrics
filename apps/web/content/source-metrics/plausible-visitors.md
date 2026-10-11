---
lede: >-
  Unique visitors are distinct people rather than page loads, and Plausible counts them without a cookie.
---

## Counted without a cookie

Plausible identifies a visitor by hashing the IP address with the user agent
and a daily rotating salt. There is no cookie and nothing persists on the
device, which is what lets Plausible run without a consent banner in most of
Europe.

The consequence is worth knowing: the hash rotates every day, so somebody who
visits on Monday and again on Tuesday is two visitors over a two-day window,
not one. Unique visitor counts over long windows are therefore closer to
visit counts than to people.

## The timezone is the site's, not yours

Daily buckets follow the timezone configured on the Plausible site, not the
one your Mac is set to. A site configured in UTC and a founder in Singapore
will disagree about where a day starts by eight hours.

Put pageviews beside this widget and the ratio tells you how many pages a
visitor reads before leaving.
