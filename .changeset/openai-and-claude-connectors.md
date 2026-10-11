---
"@notch/integrations": minor
"@notch/schemas": minor
"@notch/mac": patch
---

Add OpenAI and Claude as API-key connectors, under a new "AI" category: token
volume, request counts and daily spend.

Each provider is given the metrics it can actually answer for. OpenAI's usage
report carries a request count and Claude's does not, so Claude offers no
`api_requests` rather than an invented one.

Two ways the money goes wrong, written down because both look right: Claude's
cost report returns a decimal string already in cents, so reading `"123.78912"`
as dollars overstates the bill a hundredfold, and OpenAI returns a float in
dollars, which has to round to minor units once per bucket rather than per
line item.

Both usage APIs cap a response at 31 daily buckets, so a window is a page
count, not a call. The walk is bounded at four requests: a 90-day range drops
its comparison window to stay inside that and keeps the number, and a year is
refused with a message rather than by the Worker's CPU limit.

Cost is a separate reach from usage on both admin APIs, so a key that can read
tokens but not dollars connects with `api_spend` greyed out instead of being
rejected — but only on a refusal, since `availableMetrics` is written once at
connect and a transient 503 would hide spend until the user reconnected.

Both connectors ship their own brand mark on the brand's own tile: OpenAI's
blossom white on black, Claude's sunburst white on #D97757. simple-icons
carries neither at the title the sync script would look for, so both are
committed as overrides rather than derived at build time.
