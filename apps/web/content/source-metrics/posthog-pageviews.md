---
lede: >-
  Pageviews count `$pageview` events, which in a single-page app means whatever your router decided to send.
---

## What PostHog actually counts

A pageview is a `$pageview` event. On a server-rendered site the snippet
sends one per navigation and the number means what you expect. In a
single-page application it means whatever your router was wired to send: some
apps fire one per route change, some fire one per modal, and some fire none
after the first load because the integration was never finished.

If this figure looks an order of magnitude wrong, check the instrumentation
before you check the traffic.

## Pageviews against sessions

Pageviews divided by sessions is depth, and it is the pair worth placing
together in the notch. Depth rising is people reading more. Depth rising
while session count falls is usually a navigation problem, with the same
people hunting for something that used to be easy to find.

Buckets follow the project's own timezone.
