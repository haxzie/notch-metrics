---
name: custom-metric
description: Author a custom Notch Metrics metric through the MCP server. Use when somebody wants a number in their notch that no built-in integration provides — GitHub stars, Plausible visitors, a Postgres count, an internal API — or when a custom metric is failing with a policy, timeout or bad-result error. Covers the tool surface, the one-file plugin format, secrets, and the host allowlist.
---

# Custom metrics

A custom metric is **one ES module** on the user's own Mac, under
`~/Library/Application Support/NotchMetrics/metrics/<id>/`. The app runs it on
a schedule and draws the number in the notch. Nothing is uploaded: the code,
the keys and the results stay on the machine.

```bash
claude mcp add notch-metrics -- npx -y @notchmetrics/mcp
```

## The workflow

1. **`describe_runtime`** — the context shape, the return shape, the policy.
   One call, and it is the difference between a metric that works first time
   and three rounds of guessing.
2. **`list_providers`** — if Stripe or Dodo already provides the number, the
   user should connect that instead. Server-side, cached, no code.
3. **`test_metric`** with an inline `manifest` + `source`. Nothing is written
   to disk while iterating.
4. **`create_metric`** — stages, test-runs, and publishes only on success.
5. **`set_metric_secret`** for each declared secret.
6. Tell the user to enable it in **Settings → Custom Metrics**. A new metric
   does not run until they do.

## The module

```js
export async function fetchMetric(ctx) {
  const response = await ctx.http("https://api.github.com/repos/haxzie/notch-metrics", {
    headers: { authorization: `Bearer ${ctx.secrets.GITHUB_TOKEN}` },
  });
  if (!response.ok) throw new Error(`github returned ${response.status}`);

  const repo = await response.json();
  return { value: repo.stargazers_count, unit: "count" };
}
```

- `ctx.http` is the **only** network access — `fetch` is not available. It
  enforces `allowedHosts`, requires https, refuses private and loopback
  addresses, and caps responses at 4 MB.
- `ctx.secrets.<KEY>` — only keys declared in the manifest.
- `ctx.timeRange`, `ctx.cache`, `ctx.log`, `ctx.signal`.
- `value` **must be a number**. It is validated after the call; a string fails
  with a message naming the field rather than rendering as `NaN` three days
  later.
- Money is **integer minor units** plus a currency.

## Never write a key into the file

Declare it:

```json
"secrets": [{ "key": "GITHUB_TOKEN", "label": "GitHub token", "required": true }]
```

then `set_metric_secret`. The value goes into the macOS Keychain and reaches
the runner on stdin — not argv, which is world-readable through `ps`, and not
the environment, which is inherited by anything the plugin spawns.

`create_metric` **refuses** a source containing anything key-shaped. That
refusal is the single highest-value check in the design, because pasting the
key into the file is the natural thing to do.

## allowedHosts

Exact hostnames, or one leading `*.` matching exactly one more label. No bare
`*`: a metric that may call anywhere can post every other secret it was handed
to a pastebin, and "it needs the whole internet" is never true of a number.

If a call is blocked, `test_metric` reports it in `httpCalls` with
`blocked: true` and the host — add that host rather than guessing.

## Diagnosing a failure

| Exit / code      | Meaning                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------ |
| `policy` (4)     | A host outside `allowedHosts`, plain http, or a private address.                                             |
| `timeout` (3)    | Over `timeoutMs`. The parent `SIGKILL`s two seconds later, because a `while (true)` ignores an abort signal. |
| `bad_result` (2) | The return value is not a `PluginResult`. The message names the field.                                       |
| `manifest` (2)   | A required secret has no value, or the manifest does not parse.                                              |
| `runtime` (1)    | The plugin threw.                                                                                            |

The app keeps the last 200 lines of stderr at
`~/Library/Application Support/NotchMetrics/logs/plugins/<id>.log`, and the
Settings pane shows them with a "Copy diagnostics" button — which is what the
user pastes back to get the metric fixed.

## Be honest about the boundary

This is a **containment** boundary, not a sandbox. The metric runs with the
user's own privileges, exactly like a shell script they wrote. The policy
contains mistakes and keeps secrets from wandering; it does not defend against
code chosen to be hostile. `node:fs` reads are not blocked, and that is a
documented gap rather than an oversight.

## Before it ships

```bash
# From the repository, against a fixture:
pnpm --filter @notch/metric-runtime test
NOTCH_METRICS_ROOT=/tmp/metrics node apps/mcp/dist/index.mjs   # probe the tools
```
