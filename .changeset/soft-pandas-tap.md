---
"@notch/integrations": minor
---

Ahrefs is now connectable, in beta.

It reads backlinks, domain rating and organic keywords for a domain, from an
Ahrefs API token. Domain rating and keywords come from Ahrefs' history
endpoints, so both draw a line and compare against the previous window within
a single billed request; backlinks has no history to draw, so it reports the
live count on one date and takes a second reading only when a tile is showing
a delta. Connecting costs no API units — the token is checked against the free
limits-and-usage endpoint rather than by spending 50 units on a trial query.
