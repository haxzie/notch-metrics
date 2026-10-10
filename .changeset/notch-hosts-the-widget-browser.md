---
"@notch/mac": minor
---

Browse and add widgets inside the notch. Add Widget now opens a sidebar, a
search field and the widget list in the notch itself instead of a separate
window at the bottom of the screen, and a widget is added by clicking it
rather than dragging it across the display. The configure pane that follows
commits with Add, and Cancel takes the new widget back out.

Signed out, the notch opens on a sign-in panel — a line of explanation and
one blue Sign in button — instead of a grid of tiles each reading "Sign in".

Signing in refreshes everything built from the connections list: the Apps
pane, the connections list, the widget browser and the configure pane's
Account picker, instead of leaving the signed-out answer on screen. A widget
whose provider has exactly one account is pointed at it, so tiles added
before signing in stop reading "Connect Stripe" with Stripe connected; one
whose provider has several says "Pick a connection" instead.

A tile's hover badges — share, configure, remove — are dark frosted glass
with a larger glyph, instead of a small white disc with a glyph too small to
recognise.

Double-clicking a widget enters edit mode with that tile selected, and
pressing Delete removes the selected widget. Edit mode was otherwise a
half-second long press nobody finds, or a button at the other end of the
header from the tile being moved.
