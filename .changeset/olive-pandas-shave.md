---
"@notch/integrations": minor
---

Read private repositories on a GitHub connection.

GitHub has no read-only scope for private repositories on an OAuth app. The
only scope that reaches one is `repo`, which carries read and write on code
for every repository the signed-in account can see. That is the grant now
asked for, and the connect page says so in those terms rather than in terms
of what the connector uses.

A connection made before this keeps working for public repositories. GitHub
returns the scopes it granted on every response, so a private repository on
an older connection now says to reconnect instead of leaving a correct
repository name looking wrong.
