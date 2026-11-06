---
"@notch/mac": minor
"@notch/integrations": minor
"@notch/schemas": minor
---

Read every connector on this Mac, with no server in the path.

Provider keys are entered in the notch and stored in the Keychain, and the
adapters that use them are compiled into the app, so a credential never
reaches our servers. The connector catalogue ships as a bundled resource, so
the integration list and its forms work with no network at all.

Thirteen connectors are ported, npm is new and needs no credential, and the
four OAuth connectors are gone.

One price, five dollars, paid once.
