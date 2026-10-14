---
lede: >-
  API requests count model calls on the completions endpoint, and a batch job counts as the requests inside it rather than as one.
---

## What a request is here

One model call. If your application sends a prompt and gets a completion
back, that is a request, whatever the model and whatever the token count.

Batch jobs are the exception worth knowing. Submitting a batch of five
hundred prompts is one API call from your side and five hundred requests in
this figure. That is the honest count, because five hundred prompts were run
and five hundred prompts were billed, but it surprises anybody who expected
the number to track their own call sites.

## Requests against tokens

The two answer different questions and they diverge constantly.

Requests count how often you called. Tokens count how much you sent and
received. A product that moved from short prompts to long ones holds requests
flat and doubles tokens, and only the token figure tracks the bill.

Put [tokens](/sources/openai/tokens) beside this and the ratio between them
is your average prompt size. Watching that ratio is usually more informative
than watching either number, because it moves when your prompts change rather
than when your traffic does.

## What it is useful for

Rate limits, mostly. OpenAI limits both requests per minute and tokens per
minute, and the one you hit first depends on which of these two numbers is
growing. A product throttled on requests per minute needs batching; one
throttled on tokens per minute needs shorter prompts.

It is also the cleanest signal of whether a feature is being used at all,
because it does not move when a prompt template gets longer.

## What is not counted

Embeddings, image generation, audio and moderation calls do not appear here.
This is the completions endpoint only. A product doing a lot of embedding
work sees a request count that is a fraction of its real API usage, and an
[API spend](/sources/openai/api-spend) figure that is much larger than the
requests would imply.
