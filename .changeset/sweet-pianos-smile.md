---
"@notch/mac": patch
---

Fill a tile in a second when its range changes, rather than in ten.

Changing a widget's settings refetched the whole notch. That request is
serialised per connection and answers only when its slowest group has, so the
one tile somebody was looking at waited behind every other integration in the
layout — eight to ten seconds with a few payment providers and a GitHub
account ahead of it. A skeleton held that long does not read as a slow fetch,
it reads as a widget that never loads.

The tile whose settings changed is now fetched on its own. The whole batch is
still what a poll does, and still what answers a widget with no account yet.
