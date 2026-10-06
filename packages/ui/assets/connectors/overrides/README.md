# Full-colour connector marks

A `<id>.svg` here **wins over simple-icons** and is rendered at its own
colours on a near-white tile, rather than as a white glyph on a brand-coloured
one.

Two reasons to put a file here:

1. **simple-icons has the wrong mark.** Its Google Search Console icon is the
   pre-2021 storefront glyph, which is simply not the current logo.
2. **The brand is only recognisable in colour.** Google Analytics' shape is
   correct in simple-icons, but flat white it reads as a generic bar chart;
   the amber is the recognisable part.

Keep them square-ish and trimmed — the renderer scales to fit a square box, so
a tall viewBox just letterboxes rather than distorting. Then run:

    node scripts/sync-connector-icons.mjs
