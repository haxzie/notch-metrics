---
"@notch/integrations": minor
---

OAuth connections refresh themselves before their tokens expire. Each
connector declares how early and how often, and the Worker's cron rotates any
token inside that window; a request that arrives first does the same. GitHub
connections made with an OAuth App that issues expiring tokens no longer need
reconnecting every eight hours.
