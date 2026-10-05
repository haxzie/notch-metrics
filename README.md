# Notch Metrics

Your business metrics, in the MacBook notch. Hover the camera housing and
revenue, MRR and subscribers are there; move away and the notch looks
untouched.

![The expanded notch](.context/notch-expanded.png)

## What is here

| Path                      | What it is                                                      |
| ------------------------- | --------------------------------------------------------------- |
| `apps/mac`                | The macOS app. Swift 6, SwiftUI, XcodeGen.                      |
| `apps/api`                | Hono on Cloudflare Workers. D1, R2, Better Auth, Dodo Payments. |
| `apps/web`                | Next.js on Workers through OpenNext.                            |
| `apps/mcp`                | `notch-metrics-mcp` — lets an agent write custom metrics.       |
| `packages/schemas`        | The zod wire contracts, and the fixtures Swift decodes.         |
| `packages/integrations`   | Provider adapters. Adding one needs no app release.             |
| `packages/metric-runtime` | The custom-metric contract, executor and runner binary.         |
| `packages/db`             | Drizzle schema; migrations are generated into `apps/api`.       |
| `contracts/`              | **Generated and committed.** JSON Schema + golden fixtures.     |

## Getting started

```bash
pnpm install          # also seeds .env and apps/api/.dev.vars from the examples
pnpm dev              # web on :3000, API on :8787, MCP in watch mode
pnpm mac:run          # build and launch the Mac app
```

Prerequisites: Node 22, pnpm 10, Xcode 26, and `brew install xcodegen`. The
release pipeline additionally wants `create-dmg` — the Homebrew one, see below.

`pnpm install` fills in nothing secret. The app runs without most of
`.dev.vars`; the comments in that file say what each is for and what breaks
without it.

### Useful commands

```bash
pnpm build  pnpm typecheck  pnpm test  pnpm format
pnpm contracts            # regenerate contracts/ — CI fails if it is stale
pnpm mac:gen              # after adding, moving or deleting any Swift file
pnpm mac:test             # swift test, no Xcode scheme needed
pnpm db:generate          # drizzle migration from a schema change
pnpm db:migrate           # apply it locally
pnpm cf:bootstrap         # create the D1 database and the R2 bucket
```

## How it fits together

**Metrics are cloud-proxied.** Provider API keys are encrypted per-integration
and stored in D1; the Worker calls Stripe and returns a _normalised_ series. The
Mac app never sees a key. The encryption binds each ciphertext to its user,
integration and provider, so a row copied between users fails to decrypt rather
than decrypting into somebody else's dashboard.

**Custom metrics are local.** An agent writes one ES module into
`~/Library/Application Support/NotchMetrics/metrics/`, and the app runs it with
a compiled runner embedded in the bundle — so it works on a machine with no
Node installed. Keys live in the Keychain and reach the runner on stdin.

**Providers ship without an app release.** The settings UI renders from
`GET /v1/providers`, so adding Paddle is four files and a Worker deploy.

**Updates are a `latest.json` on R2**, served through the Worker so a bad
release can be withheld with one deploy. The app verifies the download against
both its SHA-256 _and_ the Developer ID signature — the hash alone proves only
that the file matches what the manifest said, and the manifest comes from the
same place the file does.

## Cutting a release

```bash
pnpm changeset                 # on the PR; tick @notch/mac for a Mac change
# merge to main → a "Version packages" PR appears
# merge that → an annotated mac-v<version> tag is pushed → the release runs
```

See `.claude/skills/release/SKILL.md` for the whole sequence, the two ways a
release silently does nothing, and how to roll one back.

> `create-dmg` means [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg),
> installed with Homebrew. `npm install create-dmg` is a _different tool with
> the same name_ and none of the layout flags. It must never appear in
> `package.json`.

## Testing a Dodo webhook locally

Webhooks need a public URL:

```bash
cloudflared tunnel --url http://localhost:8787
# endpoint: <tunnel>/v1/webhooks/dodo
```

Worth doing before the first real payment. The alternative is meeting the
signature path for the first time in production.

## One local-development trap

`next dev` on `:3000` calls `wrangler dev` on `:8787` cross-origin with
credentials. Both are `localhost`, which is the same site for cookie purposes,
so one sign-in covers both — _provided_ `crossSubDomainCookies` stays off.
Chrome silently discards a `Set-Cookie` carrying a dotted domain on
`localhost`, and every subsequent request simply looks signed out, with nothing
anywhere mentioning cookies.

## Licence

See `LICENSE.md`.
