---
lede: >-
  Clicks are visits that started in Google Search, and the figure for the last few days is always lower than the truth.
---

## The two to three day lag

Search Console data is not live. It settles over roughly two to three days,
and the newest buckets read low until it does. A daily sparkline therefore
droops at the right-hand end on every single refresh, on every site, and that
droop is a reporting artefact rather than a drop in traffic.

Read the trend from the settled part of the window. If you need to know
whether today was good, you will not find out today.

## Clicks are not sessions

A click is counted when somebody clicks through to your site from a Google
results page. It is not the same as a session in Google Analytics, and the
two will never agree. Search Console counts the departure from Google;
Analytics counts the arrival on your site, after redirects, consent prompts
and ad blockers have had their say. Analytics is usually lower.

Grouped Search Console totals can also undercount, because queries with very
few impressions are withheld for privacy and do not appear in any breakdown.
