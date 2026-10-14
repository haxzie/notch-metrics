---
lede: >-
  Input tokens are uncached input, cache reads and both cache-write tiers added together. The volume, not the bill.
---

## Four things, one number

Claude prices input four different ways, and this figure adds all of them
together:

Uncached input is the ordinary rate. Cache reads cost about a tenth of it,
which is the whole point of prompt caching. Cache writes cost more than
uncached input, because writing the cache is extra work, and there are two
write tiers for the five-minute and one-hour lifetimes.

So this is the volume of input, matching what the Usage page shows, and it is
deliberately not what you were charged. A product with excellent cache hit
rates has a large input token count and a small input bill.

## Which is why you cannot infer cost from it

Two applications with identical input token counts can have input bills that
differ several times over, depending entirely on how much of that input was a
cache read.

[API spend](/sources/anthropic/api-spend) is the figure to read for cost.
This one is the figure to read for how much context you are sending, which is
a design question rather than a billing one.

## Caching is the lever

If this number is large and your spend is uncomfortable, caching is almost
always the answer rather than shortening prompts. A long system prompt or a
large document sent on every request is the ideal cache candidate: written
once, read at a tenth of the price thereafter.

The cache has a lifetime, so it pays off in proportion to how often you reuse
the same prefix. Bursty traffic against a five-minute cache can end up paying
the write premium repeatedly and saving nothing.

## Reading it with output

Put [output tokens](/sources/anthropic/output-tokens) beside it. The ratio is
the shape of your workload, and it tells you which half of the bill is worth
attacking.
