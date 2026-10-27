---
"@notch/mac": patch
---

Stop asking for your Keychain password on every refresh.

A custom app that borrows a sign-in from another app read that app's
Keychain item twice per refresh, and macOS prompts for a password each time
one application reads another's item. The token is now held in memory until
it expires, so the prompt happens once rather than on every tick.
