---
title: "Writing a custom metric with Claude and MCP"
description: "Any number you can reach over HTTPS can live in your notch. One JavaScript module, a declared host list, and the code and keys never leave your Mac."
date: 2026-10-08
author: Notch Metrics
tags: [guide, custom-metrics, mcp]
faq:
  - question: What is a Notch Metrics custom metric?
    answer: >-
      A custom metric is one JavaScript module that exports a fetchMetric
      function returning a number. It lives in Application Support on your own
      Mac and runs in a runner built into the app, so no Node install is
      needed and nothing is uploaded.
  - question: Can Claude write a Notch Metrics custom metric for me?
    answer: >-
      Yes. Add the Notch Metrics MCP server with `claude mcp add notch-metrics
      -- npx -y notch-metrics-mcp`, then describe the number you want. The
      agent reads the runtime contract, writes the module, test-runs it, and
      publishes only if it returns a valid result.
  - question: Where are custom metric secrets stored?
    answer: >-
      In the macOS Keychain. They are declared in the manifest and handed to
      the runner on stdin, never on argv where any process could read them
      through ps, and never in the environment. A metric with a key written
      into its source is refused.
  - question: What can a custom metric reach over the network?
    answer: >-
      Only the hostnames its manifest declares, over HTTPS, with private and
      loopback addresses blocked and responses capped at 4 MB. A bare wildcard
      in allowedHosts is refused. This is containment, not a sandbox: the
      metric still runs as you.
  - question: Why is my custom metric failing with a policy error?
    answer: >-
      A policy error names a blocked host, a non-HTTPS URL or a private
      address. Add the host to allowedHosts in the manifest, switch the URL to
      HTTPS, and re-run test_metric. The message names the exact host or
      address that was refused.
---

Notch Metrics ships connectors for the providers most people need: Stripe,
Polar, Paddle, Dodo Payments, PostHog, GitHub. Those are server-side, cached,
and need no code from you. If your number is in one of them, connect it and
stop reading.

This post is about the other kind of number. Rows in your own Postgres. A
count from an internal admin endpoint. Visitors from a self-hosted Plausible.
Open pull requests across four repos. A custom metric is one JavaScript module
that returns that number, and it runs on your machine.

## The module

The entire contract is one exported function.

```js
export async function fetchMetric(ctx) {
  const response = await ctx.http("https://api.github.com/repos/you/your-repo", {
    headers: { authorization: `Bearer ${ctx.secrets.GITHUB_TOKEN}` },
  });
  if (!response.ok) throw new Error(`github returned ${response.status}`);

  const repo = await response.json();
  return { value: repo.stargazers_count, unit: "count" };
}
```

Three things in there are worth pointing at.

**`ctx.http` is the only network access.** There is no `fetch` in scope. The
helper requires HTTPS, refuses private and loopback addresses, caps responses
at 4 MB, and, the important one, only calls hostnames your manifest
declared. If a call is blocked, the test run tells you which host it tried.

**`value` must be a number.** It is validated after your function returns, so
a string fails immediately with a message naming the field, rather than
rendering as `NaN` in your notch three days later when you have forgotten the
metric exists.

**Money is integer minor units plus an ISO 4217 code.** Never a float. `{
value: 123456, unit: "money", currency: "USD" }` is $1,234.56. This is the
same convention the built-in connectors use, which is what lets a notch
showing Stripe and your own revenue number add them up correctly.

## Never put the key in the file

The natural thing to do with an API token is paste it into the source. Do not,
and we try hard to make it impossible: publishing a metric whose source
contains anything key-shaped is refused outright.

Declare it in the manifest instead:

```json
"secrets": [{ "key": "GITHUB_TOKEN", "label": "GitHub token", "required": true }]
```

The value then goes into the macOS Keychain and reaches the runner over stdin
and not on argv, which any process can read through `ps`, nor in the environment,
which is inherited by anything the plugin spawns.

## allowedHosts

```json
"allowedHosts": ["api.github.com", "*.mycompany.com"]
```

Exact hostnames, or one leading `*.` matching exactly one more label. A bare
`*` is refused. The reasoning is short: a metric that may call anywhere can
post every other secret it was handed to a pastebin, and "it needs the whole
internet" is never true of a single number.

This is a containment boundary, not a sandbox, and that is worth saying
plainly. It stops
exfiltration and accidental scope creep. It is not a hypervisor.

## Let Claude write it

The module is small enough to hand-write, and most of the work is reading
someone's API docs, which is exactly the work worth handing off. We publish
an MCP server for it:

```bash
claude mcp add notch-metrics -- npx -y notch-metrics-mcp
```

Then describe the number you want. The useful shape of the conversation is:

1. **`describe_runtime`**: the context shape, the return shape, the policy.
   One call, and it is the difference between a metric that works first time
   and three rounds of guessing.
2. **`list_providers`**: if a built-in connector already has the number, use
   that instead. No code, and it is cached server-side.
3. **`test_metric`** with an inline manifest and source. Nothing is written to
   disk while iterating, so you can be wrong cheaply.
4. **`create_metric`**: stages it, test-runs it, and publishes only if it
   succeeded.
5. **`set_metric_secret`** for each declared secret.

One thing to remember afterwards: a new metric does not run until you enable
it in **Settings → Custom Metrics**. That is intentional. A tool that can
write an executable module to your disk should not also be able to start it
running on a schedule without you looking at it first.

## When it breaks

The failures cluster into three kinds, and each one reports itself by name.

- **Policy**: a blocked host, a non-HTTPS URL, a private address. The test
  run lists the call with `blocked: true` and the host it wanted. Add that
  host; do not guess at a wildcard.
- **Timeout**: the runner is cancelled through `ctx.signal`. If an upstream
  API is genuinely slow, cache inside the metric with `ctx.cache` rather than
  widening the window.
- **Bad result**: the return value failed validation. The message names the
  field. Almost always a string where a number belongs, or money as a float.

Start with [the MCP server](https://www.npmjs.com/package/notch-metrics-mcp)
and one number you check too often.
