---
"@notch/integrations": patch
---

Stop a single rejected request from marking a whole connection broken.

A GitHub repository that has been renamed, mistyped or made private answers
404, and that was being reported as an authentication failure — which marked
the connection dead, asked for a reconnect that could not fix a repository
name, and stopped the connection's token being refreshed from then on. It is
now reported against the widget's repository, where the problem actually is.

Google's connectors had the same shape of fault from the other direction.
YouTube, Search Console and Analytics all answer 403 when a daily quota is
spent, and that was being read as a rejected credential rather than as a wait.
A spent quota is now a rate limit, and clears on its own.
