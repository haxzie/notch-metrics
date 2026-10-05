/**
 * What `describe_runtime` returns.
 *
 * This is the single highest-leverage tool in the server: one call replaces an
 * agent guessing at the context shape, and a guess costs a failed
 * `create_metric` plus a round of confused debugging. It is prose rather than a
 * schema dump for the same reason — the constraints need their rationale
 * attached or they read as arbitrary and get worked around.
 */
export const RUNTIME_DOCS = `
# Writing a Notch Metrics custom metric

A metric is **one ES module** with no dependencies, stored on this Mac at
\`~/Library/Application Support/NotchMetrics/metrics/<id>/metric.mjs\`,
alongside a \`manifest.json\`. The Notch Metrics app runs it on a schedule and
draws the number in the MacBook notch.

Before writing one, call \`list_providers\`. If the number is available from a
built-in integration (Stripe, Dodo Payments, Lemon Squeezy) the user should
connect that instead — it is server-side, cached, and needs no code.

## The module

\`\`\`js
export async function fetchMetric(ctx) {
  const response = await ctx.http("https://api.example.com/v1/stats", {
    headers: { authorization: \`Bearer \${ctx.secrets.EXAMPLE_API_KEY}\` },
  });
  if (!response.ok) throw new Error(\`example.com returned \${response.status}\`);

  const body = await response.json();
  return {
    value: body.total,
    unit: "count",
    series: body.daily.map((d) => ({ t: d.date, v: d.count })),
  };
}
\`\`\`

## The context

- \`ctx.http(url, { method, headers, body })\` — the **only** network access.
  \`fetch\` is not available. Enforces the manifest's \`allowedHosts\`, requires
  https, refuses private and loopback addresses, follows at most three
  redirects re-checking the host each time, and caps a response at 4 MB.
  Returns \`{ ok, status, headers, json(), text() }\`.
- \`ctx.secrets.<KEY>\` — only the keys declared in \`manifest.secrets\`.
- \`ctx.timeRange\` — \`{ from, to, granularity, timeZone }\`, ISO strings.
- \`ctx.cache.get(key)\` / \`ctx.cache.set(key, value, ttlSeconds)\` — JSON only,
  64 KB total, scoped to this metric. Use it to page a slow API hourly and
  serve the notch from the result.
- \`ctx.log(message, fields?)\` — goes to the plugin's log file.
- \`ctx.signal\` — aborts at the manifest's \`timeoutMs\`.

## The return value

\`{ value: number, unit?, currency?, series?: [{ t: ISOString, v: number }],
   previousValue?, format?, asOf? }\`

\`value\` **must be a number**. It is validated after the call; returning a
string fails with a message naming the field rather than rendering as NaN in
the notch three days later.

Money is always **integer minor units** plus a three-letter currency —
\`{ value: 123450, unit: "currency", currency: "USD" }\` is $1,234.50. Floats
are how a dashboard ends up showing \`$1,234.5600000001\`.

## Secrets

Never write a key into the file. Declare it:

\`\`\`json
"secrets": [{ "key": "EXAMPLE_API_KEY", "label": "Example API key", "required": true }]
\`\`\`

then call \`set_metric_secret\`. The value goes into the macOS Keychain and is
handed to the runner on stdin at run time. \`create_metric\` **refuses** a source
containing anything key-shaped.

## allowedHosts

Exact hostnames, or one leading \`*.\` matching exactly one more label. No bare
\`*\`. If a call is blocked, \`test_metric\` reports it in \`httpCalls\` with
\`blocked: true\` and the host, so add that host rather than guessing.

## Workflow

1. \`describe_runtime\` (this), then \`list_providers\`.
2. \`test_metric\` with an unsaved \`manifest\` + \`source\` until it returns a
   sensible number. Nothing is written to disk while you iterate.
3. \`create_metric\` — it stages, runs the metric, and only publishes if it
   produced a valid result.
4. \`set_metric_secret\` for each declared secret.
5. Tell the user to enable it in Notch Metrics → Settings → Custom Metrics. A
   new metric is not executed until they do.
`.trim();
