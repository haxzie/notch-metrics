---
"@notch/mac": patch
---

Move refresh and settings to the left of the notch header, beside the app
name. The right half carries the edit pill, the below-fold count and the
close button, and on a notched display it begins immediately after the
camera housing — so the two controls reached for most often sat furthest
from the pointer.

Fix the edit-mode well, which was framed larger than the grid and offset
outwards. Inside a ScrollView that overflows the viewport, so its left and
right bands were clipped and the dots stopped dead at the outermost tile
whatever the inset was set to. It is now the background of a padded grid,
and the padding is the gutter — so the gap around a tile matches the gap
between two of them.

Stop the header being squeezed: the panel sized the header band 10pt
shorter than the band draws itself and counted none of the content's
padding, so SwiftUI reclaimed the difference from the header's top padding.

Add a widget gallery. "Add Widget" sits beside Done in edit mode and opens
a translucent window listing every widget each connector offers, grouped
the way the server groups them. A widget is dragged from there onto the
notch, lands where the pointer let go, and opens a configuration window for
its account, size, number format, chart and range.

Use the shapes mark for Widgets everywhere it appears.

Remove the Widgets settings pane. The gallery replaces it end to end —
browse, drag in, configure — and a second way to add a widget that works
differently is worse than one. `notchmetrics://settings/widgets` still
resolves, to Apps.

Configure widgets inside the notch rather than in a window of their own. A
split: the tile on the left, its controls on the right, with the grid
sliding out and the pane sliding in. A second window thrown on screen over
whatever the user was working in — with its own focus and activation to
manage — was the wrong shape for changing the thing already on screen.

Hide the range and chart controls for metrics that cannot use them. A
snapshot — GitHub's stargazers, forks, open issues — is whatever it is right
now: there is no series to draw over thirty days and no previous window to
compare against, so both controls changed nothing.

Name the connection on a tile, not the app. Somebody with two Stripe
accounts had two tiles both saying "Stripe". Each widget can be given its own
name from its configuration, prefilled with the connection's; changing it
renames that tile only, not the account.

Refetch a widget when its configuration changes. Switching account or range
updated the stored widget but left the tile showing the old number until the
five-minute timer came round.

Draw bar charts with a solid fill. They used the sparkline's top-down
falloff, which made a short bar read as a faint one — a second meaning the
chart does not have.
