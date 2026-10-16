# Observability

Three layers, deliberately. They answer different questions and the cheapest
one that can answer yours is the one to use.

## 1. `integration_event` — what happened to one connection

A D1 table, one row per **attempt**: a metric fetch, a token refresh, a status
change, a manual verify. Written by `recordEvent` in `apps/api/src/lib/events.ts`.

This is product data, not telemetry. It is scoped to a user, it survives
independent of any vendor, and it is the thing to query when somebody asks why
their connection broke.

```sql
SELECT at, kind, outcome, metric, code, reason, http_status, duration_ms, detail
FROM integration_event
WHERE integration_id = 'int_...'
ORDER BY at DESC
LIMIT 50;
```

```bash
pnpm --filter @notch/api exec wrangler d1 execute notch --remote --env production \
  --command "SELECT at, kind, outcome, code, http_status FROM integration_event
             WHERE integration_id = 'int_...' ORDER BY at DESC LIMIT 20"
```

Notes that matter:

- **One row per attempt, not per HTTP call.** A metric that walks four pages
  writes one row; the individual calls ride along in `calls` as
  `{ host, method, status, ms }`. A row per call would multiply the write
  volume of the hot path by the page count.
- **Seven days**, swept from the cron by `sweepEvents`. Long enough for "it
  broke over the weekend", short enough that the table does not need its own
  retention policy.
- **`detail` is redacted and bounded.** `redact()` runs on it before the
  insert, not only at the console boundary — this row is kept for a week in a
  table a support query will read.
- **`recordEvent` never throws.** It watches everything else; a bug in it must
  not be able to turn a working fetch into a failed one.

### The columns worth knowing

`code` is our taxonomy — a `MetricErrorCode`, or the status a `status` row
moved to. `reason` is the provider's own word for it: `quotaExceeded`,
`bad_refresh_token`. Keep both. Our taxonomy flattens a spent quota and a
revoked token into neighbouring codes, and `reason` is what tells them apart
after the fact.

## 2. Workers Logs — the running commentary

`"observability": { "enabled": true }` in `wrangler.jsonc`. Every `console`
line, viewable in the dashboard or `wrangler tail`.

`logError` and `logInfo` in `apps/api/src/lib/redact.ts` emit **one JSON object
per line**, so these are queryable fields rather than a string to regex:

```json
{ "level": "error", "scope": "oauth.refresh.int_abc", "subsystem": "oauth", "message": "..." }
{ "level": "info", "scope": "cron.tokenRefresh", "subsystem": "cron", "candidates": 3, "refreshed": 3, "failed": 0 }
```

Scopes are dotted and the first segment is the subsystem: `oauth`, `cron`,
`metrics`, `events`. A scope that names a row carries the id as its last
segment — `metrics.fetch.int_abc` — so a line can be tied to a connection
without inferring it from what else happened nearby.

Retention here is short and the sampling is head-based. Treat it as a live
tail, not an archive.

## 3. Axiom — the archive and the dashboards

Workers Logs is not somewhere to look back from: short retention, head-based
sampling, no alerting worth the name. Axiom's free tier is 500 GB of ingest a
month, 25 GB of storage and **30-day retention** — orders of magnitude more
than this Worker produces.

### How it is wired

`apps/logs` is a **Tail Worker**. `apps/api` names it under `tail_consumers`,
so the runtime hands it every trace event the API produces — each `console`
line, each exception workerd caught itself, and the outcome of each
invocation.

**The name carries the environment.** A wrangler named environment deploys as
`<name>-<env>`, so the Workers that exist are `notch-api-production` and
`notch-logs-production`, and the `tail_consumers` entry has to say
`notch-logs-production`. Cloudflare accepts an entry naming a service that
does not exist, delivers nothing, and reports no error — an empty dataset is
the only symptom. If logs stop arriving, check this first.

```
apps/api ──trace events──▶ notch-logs ──POST /v1/ingest──▶ Axiom
             (out of band)
```

**Out of band** is the point. Delivery happens after the response has already
gone, so a slow or dead Axiom cannot turn into latency on somebody's notch.
Logging from inside the request path would put a third party's availability
inside every response.

There is no Axiom SDK. Their ingest API is one POST, and the repository's rule
against vendor SDKs in the Worker applies with force to a dependency whose
whole job is to be called on every request.

### What arrives

One Axiom event per log line, not per invocation — a line is what you filter
on. `fieldsFromMessage` parses our JSON console lines and lifts their keys to
the top level, which is the entire reason this is a Worker and not a Logpush
job: Logpush would deliver `{"scope":"oauth.refresh.int_abc",…}` as a _string_
inside `Logs[].message[]`, leaving the parsing to Axiom.

So this is queryable directly:

```kusto
['notch-metrics-api']
| where subsystem == "oauth" and level == "error"
| summarize count() by scope, bin(_time, 1h)
```

Every event carries `_time`, `worker`, `outcome` and `kind`
(`log` | `exception` | `invocation`). An invocation row is emitted even when
the request logged nothing — it is the only trace of a tick killed by
`exceededCpu`, which would otherwise be indistinguishable from a tick that
never ran.

### The APIs only

`notch-api-production` names the shipper under `tail_consumers`. The website
does not, deliberately: it is a near-static marketing site whose source calls
`console` once, so all it would contribute is request counts already visible
in Workers Analytics, diluting a dataset meant for diagnosing the API.

### What one request looks like

Every request emits exactly one line, whatever happens to it — including a
500, which is the request most worth having a record of:

```json
{
  "level": "info",
  "scope": "http",
  "subsystem": "http",
  "requestId": "9a1b2c3d4e5f6789-LHR",
  "method": "GET",
  "route": "/v1/metrics/batch",
  "status": 200,
  "ms": 412,
  "userId": "usr_...",
  "plan": "pro",
  "authKind": "device",
  "colo": "LHR",
  "spans": [
    { "name": "credentials.github", "ms": 31 },
    { "name": "provider.github.stars", "ms": 338 },
    { "name": "http.api.github.com", "ms": 102 },
    { "name": "http.api.github.com", "ms": 96, "error": "404" }
  ]
}
```

**`route`, not the path.** Hono knows the pattern that matched, so
`/v1/integrations/:id` arrives already grouped with no id in it. A raw path
would need masking — `/v1/link/:token` carries a live single-use credential —
and would still group badly. An unmatched request logs `(unmatched)`.

**`userId`, never an email address.** An id finds somebody in the database
when they write in and means nothing to anyone without it. An email address in
a third-party log store is personal data living somewhere it was never
collected to be, readable by anyone with a query token, for as long as
retention says.

**Spans are intra-request timings, not distributed tracing.** There is one
service here; a span crossing a process boundary would need propagation
nothing in this system speaks. What they answer is the question that actually
comes up — this took four seconds, how much of it was the provider. The list
is capped at 40, and a line that hit the cap says `spansDropped` rather than
quietly truncating.

```kusto
['notch-metrics-api']
| where scope == "http"
| summarize p95 = percentile(ms, 95), n = count() by route
| order by p95 desc
```

### Two events per request, joined

Each request produces an `http` line (ours) and an `invocation` row (the
runtime's, carrying the HTTP status and the Worker outcome). The shipper
copies `requestId`, `userId`, `plan` and `route` from the first onto the
second, so either one answers "whose request was this".

Note that `outcome` is the **Worker's** verdict, not the HTTP one: a 402 or a
500 is still `outcome: "ok"` as long as the isolate did not throw or get
killed. Filter on `status` for HTTP failures and `outcome` for
`exceededCpu`, `canceled` and the like.

### The request id ties the two stores together

`requestId` is `cf-ray` by preference — Cloudflare already generates one per
request and shows it in their own dashboards, so our logs and theirs name the
same thing. A caller-supplied `x-request-id` wins over it, bounded and
stripped, so a client can correlate its own retry. It goes back on every
response as `x-request-id` and is exposed through CORS, so the dashboard can
show it and a bug report can quote it.

Every `integration_event` row written while serving a request carries it too:

```sql
SELECT kind, outcome, code, http_status, duration_ms
FROM integration_event WHERE request_id = '9a1b2c3d4e5f6789-LHR';
```

So a slow line in Axiom turns into the exact provider calls behind it.

### Setting it up

```bash
# 1. In Axiom: create a dataset `notch-metrics-api` and an API token scoped to
#    ingest into it.

# 2. Give the Worker the token.
pnpm --filter @notch/logs exec wrangler secret put AXIOM_TOKEN --env production

# 3. Deploy. CI does this in the right order already; by hand it matters:
pnpm --filter @notch/logs run deploy   # must exist before the next line
pnpm --filter @notch/api run deploy    # names it under tail_consumers
```

`deploy-api.yml` deploys the shipper first for a reason: an API deploy naming
a consumer that does not exist is **accepted**, and then silently delivers
nothing.

Without `AXIOM_TOKEN` the Worker accepts events and drops them. That is
deliberate — it is what a preview deployment or a bare `wrangler dev` should
do, rather than erroring once per invocation.

**An EU Axiom organisation uses `https://api.eu.axiom.co`.** Set
`AXIOM_API_URL` in `apps/logs/wrangler.jsonc`; leaving it on the US host
returns a 401 that reads exactly like a bad token.

### Things worth knowing before you change it

- **A failed batch is not retried.** A Tail Worker that retries turns a bad
  token into a request amplifier against Axiom, and the events are already a
  minute stale by then. The failure lands in Workers Logs instead:
  `wrangler tail notch-logs-production`.
- **`notch-logs` does not ship its own logs to Axiom.** A log shipper that
  reports its own outages through itself cannot report the one that matters,
  so its `observability` stays on and its failures stay in Workers Logs.
- **Batches are split at 500 events**, so one noisy tick cannot lose the quiet
  ones alongside it to a single oversized request.

### If you would rather not run a Worker

Set `"logpush": true` on the API and create a Logpush job pointing at
`https://api.axiom.co/v1/datasets/notch-metrics-api/ingest`. No code, no second deploy, and
Cloudflare does the batching — at the cost of the field parsing above. Do not
run both: the same events would arrive twice.

## Which one to reach for

| Question                                       | Layer                                 |
| ---------------------------------------------- | ------------------------------------- |
| Why did _this_ connection break?               | `integration_event`                   |
| Is the refresh sweep keeping up?               | Axiom, `scope == "cron.tokenRefresh"` |
| What is this Worker doing right now?           | `wrangler tail notch-api-production`  |
| How often has quota-403 fired this month?      | Axiom                                 |
| What did we do before the row was overwritten? | `integration_event`                   |
| Why is nothing arriving in Axiom?              | `wrangler tail notch-logs-production` |
