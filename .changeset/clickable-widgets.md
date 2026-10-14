---
"@notch/integrations": minor
"@notch/mac": minor
---

Tiles are clickable. A click opens the number where it lives: the metric's own
page where the connector declares one — a GitHub tile goes to its repository's
stargazers, issues or Actions, filtered to the branch the widget names — and
the provider's dashboard otherwise. The configure pane's new **Opens** field
overrides both, for anyone whose useful destination is their own board rather
than the provider's.

Connectors declare `dashboardUrl`, and a metric may declare a `linkTemplate`
whose `{param}` placeholders the widget's own parameters fill. Both are
catalogue fields, so a provider that moves its dashboard fixes every existing
tile with a Worker deploy rather than an app release.
