---
"@notch/integrations": minor
---

YouTube now reports estimated revenue, ad revenue and RPM for monetised
channels.

Sign-in asks for YouTube Analytics' monetary scope, which is a superset of
the plain one rather than a second scope beside it — Google's own wording is
"monetary and non-monetary". YouTube does the currency conversion, because it
converts each day at that day's rate and converting a whole window at today's
rate is a different number from the one Studio shows. A currency YouTube
cannot pay out in falls back to US dollars and the tile says so.

Most channels are not in the YouTube Partner Program, and YouTube answers 403
to any report that so much as names a revenue column. So revenue is asked for
in its own request, leaving view counts working for everybody, and connecting
a channel without revenue succeeds with a shorter list of metrics rather than
failing. Existing connections authorised before this keep working and simply
show no revenue until they are reconnected.

RPM is revenue over views across the whole window, the way Studio computes
it, not the average of the daily rates — and not CPM, which counts only
monetised playbacks. Revenue is rounded to the cent once per window rather
than once per day, and is provisional until YouTube's month-end adjustment,
which the tile also says.
