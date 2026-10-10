---
"@notch/integrations": minor
---

The Google Ads and Meta Ads connectors are withdrawn.

Both were declared but never implemented, and both were the expensive kind of
unimplemented: a Marketing API app each, submitted for review, plus a Google
Ads developer token, before a single number could be read. The catalogue no
longer lists them, `ad_spend` and `ad_conversions` leave the metric
vocabulary with nothing left to produce them, and the website's connector
wall and its Marketing layout no longer advertise either.

Nothing a user has can break: a connector that never shipped has no
integration rows and no widgets pointing at it. A custom metric can still name
Google Ads or Meta Ads as the app its number came from — that catalogue is
deliberately a superset of the connectors, and both keep their name and accent
there alongside Linear.
