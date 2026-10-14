---
lede: >-
  Output tokens are what Claude generated, and thinking tokens are counted here too.
---

## Thinking tokens are output tokens

This is the part that catches people. When a model reasons before answering,
those reasoning tokens are output tokens and they are billed as output
tokens, whether or not your application displays them.

A product that enabled extended thinking and saw its output token count jump
has not got a bug. It is seeing the cost of the reasoning it asked for.

That makes this figure the one to watch when you turn thinking on or change a
thinking budget, because the change lands here rather than in
[input tokens](/sources/anthropic/input-tokens).

## Output is the expensive half

Output tokens are priced well above input tokens on every Claude model. The
ratio between this figure and your input tokens is therefore a better guide
to your bill than either number alone.

A retrieval-heavy product sends enormous context and generates short answers,
so input dominates the count and output can still dominate the cost. Check
[API spend](/sources/anthropic/api-spend) rather than assuming.

## Controlling it

`max_tokens` caps it, and most applications set it far above what they
render.

The thinking budget is the other lever, and it is the one with real leverage
once extended thinking is on. A budget set for the hardest request your
product makes is applied to the easiest one too unless you vary it.

## What is not here

Tokens spent by web search or code execution tools appear in
[API spend](/sources/anthropic/api-spend) rather than in this count, because
they are billed as tools rather than as model output.
