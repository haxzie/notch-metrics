---
"@notch/mac": patch
---

Fix sign-in from the Settings window, which opened the browser without its
PKCE challenge and could only ever show "this link is missing information".
