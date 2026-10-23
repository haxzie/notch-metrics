---
"@notch/mac": minor
---

Show which account this Mac is signed in as, and let it sign out.

The Account pane said "Signed in" and offered no way to leave. It now names the
email, and carries a Sign out that revokes this Mac's device token on the server
before forgetting it here — so the credential stops working rather than merely
going missing, and it does not sit in your account's device list until it
expires. Your widgets stay arranged; signing back in puts the numbers back.

The email is read from the account and falls back to "Signed in" until the
answer arrives, which on a cold launch is a moment and offline is forever.
