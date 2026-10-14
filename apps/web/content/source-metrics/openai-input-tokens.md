---
lede: >-
  Input tokens are what you sent, with cached reads and cache writes included, and audio and image inputs counted in their own units.
---

## Cached reads are counted here

The figure includes uncached input, cached reads and cache writes together,
which is what the Usage page totals. It is deliberately not what you were
billed, because cached input is priced well below fresh input.

That distinction matters the moment you adopt caching. Your input token count
barely moves and your input bill falls, which looks like a reporting error
until you know the number is measuring volume rather than cost.

For cost, read [API spend](/sources/openai/api-spend).

## Audio and image inputs have their own units

A model accepting images or audio does not count those in text tokens.
OpenAI reports them in their own token units, and this figure passes that
through rather than attempting a conversion.

So a multimodal product sees a number here that is not comparable with a
text-only one, and should not be divided by request count to get an average
prompt size in words.

## Input is usually the one you can shrink

Most applications send far more context than they need, because context is
easy to add and nobody ever removes it. Retrieval that returns ten documents
when three would do, a system prompt that accumulated instructions over a
year, a full conversation history replayed on every turn.

Three things reduce it in order of leverage: cache the stable prefix, trim
retrieval to what actually gets used, and summarise conversation history
rather than replaying it.

## Reading it with output

Put [output tokens](/sources/openai/output-tokens) beside it. Input dominating
means you are paying to send context; output dominating means you are paying
to generate. The fixes are not the same.
