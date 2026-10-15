---
name: release
description: Cut a Notch Metrics Mac release end to end. Use when someone wants to ship a new version, asks why a tag they pushed did not trigger anything, needs to re-run or recover a failed release, wants to withhold or roll back a release that is already out, or asks how latest.json and the in-app updater fit together. Covers the changesets flow, the mac-v tag, signing and notarisation, the R2 mirror, and verifying from a machine that is not the one that built it.
---

# Cutting a release

The longest and least reversible sequence in the repository: a published tag, a
notarised artefact, and a `latest.json` that every installed copy polls. Most
of what can go wrong goes wrong _quietly_.

## Before you start

- `main` is green.
- `security find-identity -v -p codesigning` shows **Developer ID Application**.
- The Version Packages pull request has been merged (see below).

## The flow

```
feature PR + changeset
        │  merge
        ▼
version.yml ──▶ opens "Version packages" PR   (versions, CHANGELOGs, Version.xcconfig)
        │  merge that PR
        ▼
version.yml ──▶ publishes @notch/mcp to npm
             └▶ pushes an annotated tag  mac-v<version>      ← using RELEASE_PAT
        ▼
release-mac.yml  archive → sign → notarise → staple → dmg → notarise → staple → GitHub release
        ▼
release-mirror.yml  upload the dmg to R2, write latest.json, verify through assets.notchmetrics.com
```

`release-mac.yml` reads `CFBundleVersion` out of the app it just built and
hands that to the mirror as an input. Do not reintroduce a read of
`Config/Version.xcconfig` in the mirror job: `mac.sh gen` rewrites that file
from `GITHUB_RUN_NUMBER`, which is a _different counter_ from the one
`version.yml` used when it committed it. The two disagreed in the direction
that makes every installed copy offer, forever, the version it is already
running.

Release notes live at `notchmetrics.com/changelog`, generated from
`apps/mac/CHANGELOG.md`. The repository is private, so a GitHub release URL in
`latest.json` is a sign-in wall for everybody but the author.

## The two traps that make a release silently do nothing

**1. A tag pushed with `GITHUB_TOKEN` raises no `push` event.** GitHub's
recursion guard suppresses it, so `release-mac.yml` never runs and nothing
anywhere says why. `version.yml` therefore pushes the tag with `RELEASE_PAT`, a
fine-grained token with `contents: write`. If a merge of the Version PR
produced no release, check that secret first.

**2. `--follow-tags` pushes annotated tags only.** `git tag mac-v0.2.0` without
`-a` reports success and leaves the tag on your machine. Always `git tag -a`.

## Releasing by hand

Sometimes the right thing, especially the first time.

```bash
# 1. The version comes from apps/mac/package.json, not from the tag.
node -p "require('./apps/mac/package.json').version"

# 2. Tag it — annotated — and push.
git tag -a mac-v0.2.0 -m "Notch Metrics 0.2.0"
git push origin mac-v0.2.0
```

That is the same trigger CI uses, which is deliberate: one code path through
the release, not two.

## Recovery

| What failed                                   | What to do                                                                                                                                                        |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The build, after the tag was pushed           | Fix, then re-run `release-mac.yml` by `workflow_dispatch` with the same tag. It is idempotent: `sign-and-notarize.sh` short-circuits on anything already stapled. |
| The mirror, after the GitHub release exists   | `R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… scripts/mirror-release.sh mac-v0.2.0`                                                                  |
| "Refuse to go backwards" fired                | Believe it. `latest.json` already points at something newer; you are mirroring an old tag.                                                                        |
| "CFBundleVersion is 0" or "is not an integer" | The build number never reached the mirror. Nothing is published, which is correct: build 0 makes a release invisible rather than broken, and that is worse.       |
| Notarisation was rejected                     | `xcrun notarytool log <submission-id> --key …`. It is the only output that names the offending binary. See the `signing` skill.                                   |

## Verifying, from a different Mac

The machine that built it is the one machine that cannot tell you whether it
works.

```bash
curl -fsSL https://assets.notchmetrics.com/desktop/latest.json | jq
curl -fsSL https://api.notchmetrics.com/v1/updates/latest | jq   # the feed the app polls

# then, on a Mac that has never built this app:
curl -LO "$(curl -fsSL https://assets.notchmetrics.com/desktop/latest.json | jq -r .url)"
spctl -a -t open --context context:primary-signature -v NotchMetrics-*.dmg
```

Expect `source=Notarized Developer ID`. Anything else means users will see a
warning. Then actually mount it, drag it to `/Applications`, and launch — with
Gatekeeper on.

## Rolling back

**Set `PINNED_VERSION` on the Worker and deploy. Do not rewrite `latest.json`.**

```bash
# apps/api/wrangler.jsonc, production vars:
#   "PINNED_VERSION": "0.1.9"
pnpm --filter @notch/api deploy
```

This is the entire reason the app polls `/v1/updates/latest` rather than R2
directly: one deploy stops every client being offered the bad build, with no
bucket rewrite and no CDN TTL to wait out. Rewriting `latest.json` means a
minute of propagation and leaves the bad disk image reachable at its pinned
URL anyway.

Clients that already updated are not rolled back. There is no mechanism for
that and there should not be.

## Before it ships

```bash
node scripts/check-release-env.mjs      # refuses a build pointing at localhost
scripts/verify-signature.sh apps/mac/build/export/NotchMetrics.app
scripts/verify-signature.sh apps/mac/build/NotchMetrics-*.dmg
```
