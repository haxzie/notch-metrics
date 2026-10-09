---
name: deploy
description: Deploy the API Worker and the website to Cloudflare. Use when someone wants to push apps/api or apps/web live, asks why a NEXT_PUBLIC_ change did not take effect after a deploy, needs to set or rotate a Worker secret, wants to roll back a deployment, or asks why migrations run before the deploy rather than after. Covers wrangler, OpenNext, the secret split, and what wrangler rollback does and does not undo.
---

# Deploying

Two deployments, one Cloudflare account, one API token. CI does both on a push
to `main` that touches the relevant paths; everything here also works by hand.

## The API

```bash
pnpm --filter @notch/api typecheck
pnpm --filter @notch/api test
pnpm --filter @notch/api migrate:remote     # BEFORE the deploy
pnpm --filter @notch/api run deploy      # `run` matters: bare `deploy` is pnpm's own command
```

**Migrations first, always.** Every migration in this repository is additive,
so the old code keeps working against the new schema for the few seconds in
between. The other order puts new code live against a schema that does not have
its tables yet, and every request 500s until the migration lands.

This is also why `deploy-api.yml` sets `cancel-in-progress: false`: a run
cancelled between the two steps leaves the schema ahead of the code, which is
the one state nothing here recovers from automatically.

## The website

```bash
pnpm --filter @notch/web run deploy          # opennextjs-cloudflare build && deploy
```

**`NEXT_PUBLIC_*` is inlined at build time.** Changing one on the deployment
does nothing; it needs a rebuild. That is why `deploy-web.yml` sets them as job
environment variables rather than as Worker vars.

OpenNext on Workers rather than Pages: Pages cannot run this version of Next,
and `@cloudflare/next-on-pages` is edge-runtime-only — which the `/download`
route handler is not.

## Secrets never go through CI

```bash
wrangler secret put BETTER_AUTH_SECRET --env production
wrangler secret put INTEGRATION_KEK_V1 --env production
wrangler secret put DODOPAYMENT_API_KEY --env production
wrangler secret put DODOPAYMENT_WEBHOOK_SECRET --env production
wrangler secret put SLACK_WEBHOOK_SIGNUPS --env production
wrangler secret put SLACK_WEBHOOK_EVENTS --env production
```

The two Slack ones are optional — an unset webhook makes `lib/slack.ts` a
no-op rather than an error, which is what a staging stack wants. A webhook URL
_is_ the credential and is bound to one channel, so moving a notification to a
different channel is a new URL here, not a code change.

Set once; they survive every deploy. Pushing a payment key through CI means a
second copy in a second place for no gain.

Non-secret configuration — URLs, Dodo _product_ ids, the active KEK version —
lives in `wrangler.jsonc` with a comment saying why each is not a secret.

> **A named environment inherits nothing.** Every var in the top-level `vars`
> block must be repeated in `env.production.vars`, or it is simply absent in
> production. For most of them that is silence rather than an error.

## Rolling back

```bash
wrangler rollback --env production           # the Worker only
```

**It does not roll back a D1 migration.** Since migrations only ever add, that
is usually fine: the old code ignores the new column. If you ever need to undo
a migration, that is a second, forward migration — see `db-migration`.

## Path filters

`deploy-api.yml` watches `apps/api`, `packages/db`, `packages/schemas`,
`packages/integrations` and the lockfile. `deploy-web.yml` watches `apps/web`,
`packages/ui`, `packages/env`, `packages/schemas`. A change they do not catch
needs a `workflow_dispatch`.

## Before it ships

```bash
curl -fsS https://api.notchmetrics.com/health
curl -fsS https://api.notchmetrics.com/v1/providers | jq '.providers[].id'
curl -fsSI https://notchmetrics.com/download | head -1     # expect a 302
```
