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

## How a list is drawn

A \`list\` metric's rows can be drawn as a **distribution** — the categories
against each other — rather than as text. The user picks, but the shapes are
worth knowing when you decide what to return:

- **ranked** — one labelled bar per category, largest first. The default, and
  the one that survives long names.
- **split** — one bar divided into coloured segments. Fits a single row.
- **pie** — the whole as a circle. Wants a square tile.

All three need a magnitude per row. Put it in \`amount\` where there is a real
number; a figure inside \`detail\` is read as a fallback. A list with neither
is drawn as equal slices, which says these are the categories without
inventing weights.

## Where a field belongs

Two places, and the split is not a style preference — it decides what the user
can change and how often the app asks.

**\`auth\` is app level, and holds credentials only.** What proves who you
are: a token, a key, an account subdomain. Asked once, stored in the Keychain,
shared by every metric the app offers.

**\`params\` is metric level, and holds values.** What says *which thing* to
measure: a package name, a repository, a project id. Asked per widget, stored
in the layout, and sent to \`fetchMetric\` as \`request.params\`.

The test is whether two tiles could reasonably want different answers. A
package name belongs in \`params\` — one app should serve a tile for \`zod\`
and a tile for \`react\` at once. Putting it in \`auth\` locks the whole app
to one package and makes an identifier look like a secret.

\`\`\`json
"authMode": "none",
"auth": [],
"metrics": [{
  "id": "downloads",
  "params": [{ "key": "package", "label": "Package", "type": "string",
               "required": true, "placeholder": "zod" }]
}]
\`\`\`

## Authentication

There is no OAuth and there will not be: a refresh needs a client secret, and
a client secret on a laptop is a published client secret.

A **free or public API needs no credentials at all**. Say so:

\`\`\`json
"authMode": "none", "auth": []
\`\`\`

That is also the right mode for an app that holds its own credential in its
code. Nothing is asked of the user, no Keychain entry is read, and the
Settings row says "No credentials needed" rather than showing an empty form.

Otherwise declare what the user must supply:

\`\`\`json
"authMode": "api_key",
"auth": [{ "key": "api_key", "label": "API key", "type": "secret", "required": true }]
\`\`\`

Declaring \`none\` alongside fields is refused rather than silently resolved.

The fields are rendered as a **form inside the app**, in Settings → Custom
Apps. Credentials belong to the app, not to a widget: one key answers every
metric behind it, so they are asked for once.

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

## The icon

Declare it in the manifest. Do not ship a PNG unless the app has a real logo —
you almost certainly want a symbol:

\`\`\`json
"icon": { "type": "symbol", "name": "shippingbox.fill", "tint": "#FF6B00" }
\`\`\`

\`name\` is an **SF Symbol** — the names in Apple's SF Symbols app, lower-case
words separated by dots: \`chart.bar.fill\`, \`person.2\`, \`cart\`,
\`shippingbox\`. A name this macOS does not have falls back to the generic
mark, so prefer long-standing ones over the newest additions. \`tint\` is the
tile behind the glyph and defaults to the Custom accent.

Building against a service Notch Metrics already knows? Borrow its mark — the
icon *and* the tile colour come from one place, so it looks like that service
without shipping a logo of your own that drifts from ours:

\`\`\`json
"icon": { "type": "app", "appId": "anthropic" }
\`\`\`

The other arms:

\`\`\`json
"icon": { "type": "emoji", "value": "📦" }
"icon": { "type": "file", "path": "icon.png" }
\`\`\`

\`file\` is a **file name inside the connector directory** — never a path and
never a URL. Omit \`icon\` entirely and the app draws its generic \`{}\` mark,
which is fine but makes every custom app look alike in the notch.

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
