---
"@notch/integrations": patch
---

Every connector manifest's `iconPath` now points at a URL that exists.

All eighteen said `/providers/<id>.svg`; the website has only ever served
`/connectors/<id>.svg`, and the assets host named in the field's own
description serves neither — it mirrors releases. Nothing rendered from the
field, because both clients resolve a mark from the connector id instead, so
nothing noticed. A test now pins the value, since a field nothing reads is a
field nothing notices has gone stale.
