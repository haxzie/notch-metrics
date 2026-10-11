---
lede: >-
  Events are every action PostHog captured, which makes this the broadest and the noisiest number PostHog reports.
---

## Everything counts, including the autocapture

PostHog counts every event ingested in the window: your own named events, the
automatic `$pageview` and `$pageleave`, and, if autocapture is on, a
`$autocapture` event for most clicks and form submissions on the page. A
product with autocapture enabled produces an event volume several times what
its own instrumentation would suggest.

That is useful for one thing in particular. Event volume is what PostHog
bills on, so this widget is the closest thing to a live view of next month's
invoice.

## Reading it

As a product signal it is weak, because a single noisy component can double
it without a single extra user arriving. Put active users beside it. Events
climbing while active users hold flat means you shipped more tracking, not
more usage.

Buckets follow the project's own timezone.
