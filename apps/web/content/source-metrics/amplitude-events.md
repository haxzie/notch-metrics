---
lede: >-
  Events are every action Amplitude ingested in the window, and Amplitude's daily buckets are not negotiable.
---

## No hourly bucket, on purpose

Amplitude's Dashboard REST API serves daily, weekly and monthly intervals.
There is no hourly option, so the widget offers none rather than
manufacturing one by splitting a day into twenty-four equal pieces. A
sparkline that invents its own resolution is worse than a coarser one.

## What counts as an event

Everything your instrumentation sends, under whatever names you gave it.
Amplitude does not autocapture by default, so unlike PostHog this figure
reflects deliberate tracking rather than a framework's opinion of what a
click is. That makes it a cleaner product signal and a less useful billing
signal.

Amplitude also charges on event volume, so a sudden climb with no release
behind it is worth tracing to the component that started shouting.

Buckets follow the project's own timezone, which is set in Amplitude and not
on your Mac.
