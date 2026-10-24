# @notchmetrics/core

Types and schemas for writing a **local connector** for
[Notch Metrics](https://notchmetrics.com).

A connector is one app, its credential, and every metric it offers. It runs on
your own Mac against your own API key, and is never uploaded.

```bash
npm install @notchmetrics/core
```

## Nothing here is required at run time

A connector exports two plain functions and the runner supplies the context.
This package exists so that writing one in TypeScript is checked by the
compiler, rather than by `register_connector` rejecting it afterwards.

```ts
import type { ConnectorContext, MetricRequest } from "@notchmetrics/core";

export async function verify(ctx: ConnectorContext) {
  const r = await ctx.http("https://api.linear.app/graphql", {
    method: "POST",
    headers: { authorization: ctx.credentials.api_key },
    body: JSON.stringify({ query: "{ viewer { name } }" }),
  });
  if (!r.ok) throw new Error(`Linear returned ${r.status}`);
  const body = await r.json<{ data: { viewer: { name: string } } }>();
  return { accountLabel: body.data.viewer.name };
}

export async function fetchMetric(ctx: ConnectorContext, request: MetricRequest) {
  if (request.metric === "open_issues") return { value: await count(ctx) };
  throw new Error(`unhandled ${request.metric}`);
}
```

Build it to a single ES module and register it with the Notch Metrics MCP
server. Bundled output is expected — `export { verify, fetchMetric }` is as
good as `export async function`.

## The four shapes

`shape.kind` decides which controls the tile offers and what `fetchMetric`
must return.

| kind     | what it is                              | return                             |
| -------- | --------------------------------------- | ---------------------------------- |
| `scalar` | one number for right now, no window     | `{ value }`                        |
| `series` | a number per bucket over a window       | `{ value, points, previousValue }` |
| `total`  | one number _for_ a window, no breakdown | `{ value, previousValue }`         |
| `list`   | rows of what just happened              | `{ value, items }`                 |

Use `scalar` when the API reports a current count and offers no history — a
flat line invented from one reading looks like data and is not. Use `total`
when the API answers a window total but cannot be bucketed without one request
per point.

## Rules worth knowing before you write one

**`ctx.http` is the only network access.** It enforces your manifest's
`allowedHosts`, requires https, refuses private and loopback addresses,
re-checks the host on every redirect hop, and caps a response at 4 MB. A bare
`fetch` bypasses all of it.

**Money is integer minor units** plus an ISO 4217 code. Never a float. A
`currency` metric returning `20.69` renders as 20 cents.

**Never write a credential into the file.** Declare it in `auth` and set the
value with `set_connector_credential`; it is kept in the macOS Keychain and
handed to the runner on stdin. Registration refuses a source containing
anything key-shaped, because pasting the key in is the natural thing to do
with one.

**`allowedHosts` takes exact names or one leading `*.`.** No bare `*`.

## This is a containment boundary, not a sandbox

A connector runs with your own privileges, like a shell script you wrote. The
host allowlist and the credential handling contain mistakes and stop keys
wandering. They do not defend against code written to be hostile — so treat a
connector you did not write the way you would treat any other program.

## Licence

MIT
