# Working in this repository

Standing rules. Workflows live in `.claude/skills/` — `release`, `mac-dev`,
`signing`, `deploy`, `db-migration`, `versioning`, `add-integration`,
`custom-metric`.

## Comments earn their place

A comment here explains **why**, and ideally names the failure it prevents. A
comment restating the code is noise; a comment saying "`set_key_partition_list`
is mandatory or codesign blocks on a prompt no runner can answer" is the
difference between a five-minute fix and a lost afternoon.

Non-obvious decisions get one. Obvious ones get none.

## Never do these

- **Hand-edit** a `version` field, a `CHANGELOG.md`, `Version.xcconfig`, or
  anything under `contracts/`. All are generated.
- **Commit** `apps/mac/NotchMetrics.xcodeproj`, `Config/Config.xcconfig`,
  `.env`, `.dev.vars`, or a `.p12`/`.p8`.
- **Add an `info:` block** for the app target in `project.yml`. It makes
  XcodeGen _generate_ a plist over the hand-written one, and `LSUIElement` and
  the URL scheme quietly disappear.
- **Set `MARKETING_VERSION`** anywhere in `project.yml`. A build setting at any
  level overrides the xcconfig — including an empty one, which reverts the app
  to Xcode's `1.0` default while the xcconfig sits alongside looking correct.
- **Use `cp -R` on an app bundle.** `/usr/bin/ditto`, always.
- **Add a vendor SDK** to the Worker for a handful of GETs.
- **Reach for `disable-library-validation`.** The real cause is an unsigned
  nested binary.

## House conventions

- Money is **integer minor units** plus an ISO 4217 code. Never a float.
- Every enum crossing the wire decodes with an `unknown` fallback on the Swift
  side and stays strict on the server side. That asymmetry is what lets a new
  provider ship without breaking installed apps.
- `noUncheckedIndexedAccess` is on. The `scalar()` helper in the test suites
  exists for exactly this.
- Imports in `packages/` and `apps/api` carry `.ts` extensions —
  `verbatimModuleSyntax` plus `rewriteRelativeImportExtensions` is what lets
  the Worker and vitest run the sources with no build step. `apps/web` does
  not, because Next re-resolves them.
- Prettier, 100 columns. `pnpm format` before committing.

## Where the contracts are

`packages/schemas` is the single definition of every wire shape. `pnpm contracts`
emits JSON Schema and golden fixtures into `contracts/`, both committed.

The Swift models are **hand-written** and `apps/mac/Kit/Tests/ContractTests`
decodes those same fixtures. That is what catches drift: a renamed field fails
the Swift suite by name, in CI, rather than at a user's launch as a decode
error that blanks every widget at once.

So: change a wire shape → `pnpm contracts` → fix the Swift structs → commit all
three together.

## Security boundaries worth knowing

- A user's provider key is encrypted with a per-integration key, with the
  user, integration, provider and key version bound in as AAD. A row copied
  between users does not decrypt. Never remove the AAD.
- Never delete an `INTEGRATION_KEK_*` secret while any row still names that
  version. Those integrations become permanently unreadable and there is no
  backup of somebody's Stripe key.
- Custom metrics are a _containment_ boundary, not a sandbox. Say so rather
  than implying otherwise.
- `/v1/...` returns **404, not 403**, for a resource belonging to another
  user. A 403 confirms it exists.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
