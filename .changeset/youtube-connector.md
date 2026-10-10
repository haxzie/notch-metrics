---
"@notch/integrations": minor
"@notch/mac": minor
---

YouTube is connectable, in beta: views, watch time, average view duration,
subscribers, new subscribers, likes and comments for a channel you own.

Sign-in uses the same Google client as Analytics and Search Console, so there
is nothing new to authorise beyond the channel's read-only scopes, and the
hour-long token refreshes in the background. Pick the channel after signing
in — a brand account's channel is rarely the one the sign-in name suggests.

Everything time-ranged comes from one YouTube Analytics report, so average
view duration is watch time over views for the whole window rather than the
mean of the daily averages. The subscriber total is YouTube's own, which it
rounds above a thousand; the change against the previous window is the exact
net gain, so the arrow is right even where the total reads as 12,300. New
subscribers is gross, so it does not match that change.
