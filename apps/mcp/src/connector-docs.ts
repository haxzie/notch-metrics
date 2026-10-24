/**
 * What an agent is told before it writes a connector.
 *
 * Prose rather than a schema dump, for the same reason `RUNTIME_DOCS` is: the
 * constraints need their rationale attached or they read as arbitrary and get
 * worked around. An agent that knows *why* `allowedHosts` exists does not try
 * to widen it to `*`.
 */
export const CONNECTOR_DOCS = `# Writing a local connector

A connector is **one app, one credential, many metrics** — the unit somebody
actually has. It lives at
\`~/Library/Application Support/NotchMetrics/connectors/<id>/\`, runs on this
Mac with the user's own key, and is never uploaded.

Use a connector when several numbers come from one account. Use
\`create_metric\` when there is genuinely only one.

## Before you start

Call \`list_providers\`. If the numbers already come from a built-in connector,
the user should connect that instead — it has OAuth, server-side caching and
notifications, none of which a local connector gets.

## The module

Two exports. Build your project to a single ES module if you like — bundled
output is accepted, and \`export { verify, fetchMetric }\` is as good as
\`export async function\`.

\`\`\`js
export async function verify(ctx) {
  const r = await ctx.http("https://api.linear.app/graphql", {
    method: "POST",
    headers: { authorization: ctx.credentials.api_key, "content-type": "application/json" },
    body: JSON.stringify({ query: "{ viewer { name } }" }),
  });
  if (!r.ok) throw new Error(\`Linear returned \${r.status}\`);
  const body = await r.json();
  return { accountLabel: body.data.viewer.name };
}

export async function fetchMetric(ctx, request) {
  switch (request.metric) {
    case "open_issues":
      return { value: await count(ctx) };
    default:
      throw new Error(\`unhandled \${request.metric}\`);
  }
}
\`\`\`

\`verify\` proves the credential and names the connection. It runs before the
connector is registered: a key that does not work must not become a connector
that silently shows nothing for a week.

\`fetchMetric\` is called once per metric per tick, **in one process**. Do not
assume a fresh process per metric.

## The context

- \`ctx.credentials.<key>\` — only the keys your \`auth\` declares. Anything else
  is filtered out before your code runs.
- \`ctx.http(url, { method, headers, body })\` — the **only** network access.
  Enforces \`allowedHosts\`, requires https, refuses private and loopback
  addresses, follows at most 3 redirects re-checking the host on each, and
  caps a response at 4 MB. Returns \`{ ok, status, headers, json(), text() }\`.
- \`ctx.timeRange\` — \`{ from, to, granularity, timeZone }\` for this request.
- \`ctx.log(message, fields?)\`, \`ctx.signal\`.

## The four shapes

\`shape.kind\` decides which controls the tile offers and what you must return.
Getting it wrong produces a widget that lies rather than an error.

| kind | what it is | return |
| --- | --- | --- |
| \`scalar\` | one number for right now, no window | \`{ value }\` |
| \`series\` | a number per bucket over a window | \`{ value, points, previousValue }\` |
| \`total\` | one number *for* a window, no breakdown | \`{ value, previousValue }\` |
| \`list\` | rows of what just happened | \`{ value, items }\` |

Pick \`scalar\` when the API reports a current count and offers no history — a
flat line invented from one reading looks like data and is not. Pick \`total\`
when the API answers a window total but cannot be bucketed without one request
per point. Only \`series\` and \`total\` take \`granularities\`, because they are
the only ones where a range means anything.

\`granularities\` is a promise. Declaring \`month\` means the pane offers "12m"
and your code must answer it; declaring too few silently hides a range.

## Credentials

Declare them, never write them into the file:

\`\`\`json
"auth": [{ "key": "api_key", "label": "API key", "type": "secret" }]
\`\`\`

Keys are lower-case — \`api_key\`, not \`API_KEY\` — matching the built-in
connect forms, which is what renders them. \`type: "secret"\` masks the field.

Then call \`set_connector_credential\`. The value goes into the macOS Keychain
and reaches the runner on stdin: not argv, which is world-readable through
\`ps\`, and not the environment, which is inherited by anything your code
spawns.

**Registration refuses a source containing anything key-shaped.** Pasting the
key into the file is the natural thing to do with one, which is exactly why
it is checked.

## allowedHosts

Exact hostnames, or one leading \`*.\` matching exactly one more label. No bare
\`*\`: a connector that may call anywhere can post the credential it was handed
to a pastebin, and "it needs the whole internet" is never true of a number.

A blocked call comes back in \`httpCalls\` with \`blocked: true\` and the host —
add that host rather than guessing.

## Money

Integer **minor units** plus an ISO 4217 code. Never a float. A \`currency\`
metric returning \`20.69\` renders as 20 cents.

## Registering

1. \`register_connector\` with the manifest, the source and any credentials.
   It stages, verifies, fetches every metric once, and publishes only if that
   worked — so a broken build cannot blank working tiles.
2. \`refresh_connector\` to replace one you have rebuilt.
3. Tell the user to enable it in **Settings**. A new connector does not run
   until they do, and because approval is pinned to the contents, a refresh
   asks again.

## This is a containment boundary, not a sandbox

The connector runs with the user's own privileges, like a shell script they
wrote. The host allowlist and the credential handling contain mistakes and
stop keys wandering; they do not defend against code written to be hostile.
Say so if asked rather than implying otherwise.
`;
