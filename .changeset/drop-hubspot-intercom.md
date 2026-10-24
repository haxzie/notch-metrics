---
"@notch/schemas": minor
"@notch/integrations": minor
---

Remove the HubSpot and Intercom connectors.

Both were declared and never implemented: `status: "coming_soon"` since the
day the catalogue was added, every metric throwing `notImplemented`, and
`connectable()` filtering them out. Nobody has ever connected one, so there
are no rows, no widgets and nothing to migrate — which is the only reason
this is a deletion rather than a deprecation.

They were also the only two connectors in the CRM category, so the category
goes with them along with the six metric ids nothing else declared —
`contacts`, `new_contacts`, `open_deals`, `won_deals`, `pipeline_value` and
`open_conversations`. Leaving those behind would have recreated the problem
`arr` and `conversion_rate` already are: ids in the enum that no provider
serves, which nothing fails over and nobody notices.

`ProviderId`, `MetricId` and `ConnectorCategory` all shrink, so this is a
wire change and `contracts/` is regenerated with it. No golden fixture moved
— none of them named a removed value — and the Swift models read these as
strings with a fallback, so an installed app meeting the smaller catalogue
decodes it fine.

The marketing site loses its Sales layout, which was nine-tenths HubSpot and
Intercom. Its own note said leaning on "Soon" connectors was deliberate
because it showed where the product was going; with them gone it showed where
it is not. Rebuilding it from revenue widgets would have made a second
Founders layout, so it went instead. The hero glyph that was HubSpot is now
Claude, which keeps the hand-placed composition intact.
