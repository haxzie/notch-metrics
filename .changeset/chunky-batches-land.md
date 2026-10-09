---
"@notch/mac": patch
---

A notch with more than twelve widgets now loads at all. The server caps a
metrics batch at twelve and rejects the whole body past that, so a thirteenth
widget made every tile read "Could not reach Notch Metrics". Requests are split
to fit, and a rejected request, an ended trial and a signed-out app each say so
instead of blaming the network.
