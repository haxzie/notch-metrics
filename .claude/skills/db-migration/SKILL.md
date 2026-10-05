---
name: db-migration
description: Change the D1 schema with Drizzle. Use when someone adds a table or a column, asks where migrations live or why wrangler cannot find them, hits an error naming a column that should exist, wants to rename or drop something, or asks why the deploy applies migrations before deploying. Owns the additive-only rule that makes the deploy ordering safe.
---

# Changing the database

## The loop

```bash
# 1. Edit packages/db/src/app-schema.ts
pnpm db:generate            # drizzle-kit writes apps/api/migrations/NNNN_*.sql

# 2. READ the generated SQL. Every time.
cat apps/api/migrations/*.sql | tail -40

# 3. Apply locally and prove it works.
pnpm db:migrate
pnpm --filter @notch/api test

# 4. Commit the schema change and the migration together.
```

A schema change committed without its migration is a deploy that fails at the
migrate step; a migration committed without its schema change is one that
drizzle will try to generate again next time.

## Additive only

**No drops. No renames. No `NOT NULL` without a default.**

This is not style. `deploy-api.yml` applies migrations _before_ deploying, so
for a few seconds the old code is serving traffic against the new schema. An
additive migration is invisible to it. A destructive one breaks every request
in flight.

Renaming `foo` to `bar` is therefore two releases:

1. Add `bar`, write to both, read `foo`. Deploy. Backfill.
2. Read `bar`. Deploy. _Then_ a later migration drops `foo`.

Tedious, and it is the difference between a deploy and an incident.

## Where migrations live, and why not in packages/db

`packages/db/drizzle.config.ts` writes to `../../apps/api/migrations`.

`wrangler d1 migrations apply` resolves `migrations_dir` **relative to
wrangler.jsonc**, so a migrations directory anywhere else is one wrangler will
not find — and it reports "no migrations to apply", which reads as success.

## One logical change per file

D1 gives no transactional DDL worth relying on. A migration that half-applies
leaves the database in a state no code expects, and the smaller the file the
smaller that state is.

## Local reset

```bash
pnpm db:reset      # rm -rf .wrangler/state/v3/d1 && migrate
```

You will want this weekly early on. If a query errors naming a column that is
clearly in the schema, the local D1 is behind — reset rather than debug.

## Better Auth tables

`packages/db/src/auth-schema.ts` is hand-written to match what Better Auth
expects. `test/schema-matches-better-auth.test.ts` asserts they still agree, so
an upgrade that changes a column fails in CI rather than at a user's first
sign-in.

Three app columns live on `user` — `plan`, `timezone`, `preferred_currency` —
because `plan` is read on nearly every request and a join for it would be a
second D1 round trip on the hot path. They are declared to Better Auth as
`additionalFields` with `input: false`, which is what stops a client setting
its own plan.

## Before it ships

```bash
pnpm db:generate && git diff --stat apps/api/migrations
pnpm --filter @notch/api test
grep -iE 'DROP |RENAME |ALTER .* NOT NULL' apps/api/migrations/*.sql   # expect nothing
```
