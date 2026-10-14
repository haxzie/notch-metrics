---
lede: >-
  Output tokens are what the model generated, which is the expensive half of most bills.
---

## Output costs several times more than input

On most OpenAI models, output tokens are priced at a multiple of input
tokens. That makes the split between the two the single most useful thing to
know about your usage.

A product whose [input tokens](/sources/openai/input-tokens) dominate is
paying to send context. One whose output dominates is paying for generation.
They call for completely different optimisations: the first wants shorter
prompts and caching, the second wants shorter responses and a smaller model.

Looking only at [total tokens](/sources/openai/tokens) hides which of those
you are.

## What counts as output

Everything the model generated on a completions request in the window,
including the parts your application discarded. A response truncated by your
own code still generated and still billed.

Structured outputs and tool calls are output tokens too. A model returning a
large JSON object is producing tokens at the output rate, which is why a
chatty tool schema can cost more than the prose it replaced.

## Reducing it

`max_tokens` is the blunt instrument and it works. Most products set it far
higher than anything they actually render.

Beyond that, output length responds to the prompt more than people expect.
Asking for a short answer usually produces one, and asking for structured
output with a tight schema produces less than asking for prose.

## Reading it against spend

Put [API spend](/sources/openai/api-spend) beside this. Output tokens rising
faster than spend means you moved to a cheaper model; spend rising faster
than output tokens usually means input grew, or you moved to a more expensive
one.
