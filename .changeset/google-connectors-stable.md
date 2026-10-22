---
"@notch/integrations": patch
---

Google Analytics, Search Console and YouTube are out of beta.

Google has verified the OAuth client the three of them share, so the consent
screen they lead into is no longer the one warning people the app is
unverified, and the hundred-test-user cap on who can reach it is gone.

Nothing about the connectors themselves changed, and nothing in the app was
gated on the verification: the scopes are the ones they always asked for, and
all three have been connectable since they shipped. What moves is the badge
on their source pages and their rank in the registry, both of which said
"beta" on connectors whose edges are no longer being worked on.

The Limited Use disclosure on the connect page stays exactly where it is.
Google's API Services User Data Policy requires it on the screen leading into
consent whether or not the client is verified, and it is the kind of thing an
approval is withdrawn over.
