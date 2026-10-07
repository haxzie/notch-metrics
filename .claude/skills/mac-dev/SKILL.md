---
name: mac-dev
description: Build, run, test and debug the Swift app in apps/mac. Use when someone adds, moves or deletes a Swift file, asks why a new type "cannot be found in scope", wants to run the notch locally, sees a stale copy running after a build, is looking for the app's logs or its on-disk state, hits a Keychain error after switching signing identities, or needs a deterministic screenshot of the expanded notch. Covers xcodegen, the build scripts, the debug environment variables, and the traps that look like compiler or code bugs but are not.
---

# Working on the Mac app

## Where things are

| Path                               | What it is                                                |
| ---------------------------------- | --------------------------------------------------------- |
| `apps/mac/project.yml`             | The project. Edit this, never the Xcode UI.               |
| `apps/mac/NotchMetrics.xcodeproj`  | **Generated. Gitignored. Never commit or edit.**          |
| `apps/mac/App/`                    | The app target: delegate, scenes, settings panes.         |
| `apps/mac/Kit/Sources/`            | Where the logic lives, as five library targets.           |
| `apps/mac/Config/Version.xcconfig` | Generated **and committed**. From the changesets version. |
| `apps/mac/Config/Config.xcconfig`  | Generated, gitignored. The URLs the app talks to.         |
| `apps/mac/Helper/UpdateInstaller/` | The signed CLI that swaps the bundle during an update.    |
| `scripts/mac.sh`                   | `gen`, `run`, `test`, `open`.                             |

## The one trap that will cost you an hour

**A new `.swift` file does not exist until `xcodegen` has run.** The compiler
reports this as `cannot find 'Foo' in scope` at the _use_ site, which sends you
looking at imports, access levels and target membership — none of which are the
problem.

```bash
pnpm mac:gen        # after adding, moving, renaming or deleting any file
```

`mac.sh gen` also regenerates both xcconfigs, so it is the safe thing to run
whenever something seems out of date.

Corollary: **never change build settings in Xcode's inspector.** They land in
the generated `.xcodeproj` and vanish on the next generate, which looks like
Xcode forgetting your setting.

## Everyday loop

```bash
pnpm mac:gen                 # after any file change
pnpm mac:run                 # build + launch (unsigned, Debug)
pnpm mac:test                # swift test in Kit — no Xcode scheme needed
pnpm mac:ship                # build Release, sign, install to /Applications
```

`pnpm mac:test` runs `swift test` rather than an Xcode test bundle on purpose:
it needs no scheme, so CI does not have to generate the project to run it.

## Debug environment variables

The notch is awkward to inspect because it hides when the pointer leaves it.

| Variable               | Effect                                                   |
| ---------------------- | -------------------------------------------------------- |
| `NOTCH_DEBUG_EXPAND=1` | Open and **pin** the notch at launch.                    |
| `NOTCH_DEBUG_EDIT=1`   | Start in edit mode — dotted grid, resize handles.        |
| `NOTCH_DEBUG_DEMO=1`   | Plausible numbers instead of "Sign in". For screenshots. |
| `NOTCH_DEBUG_GALLERY=1`| Open the Add Widgets gallery at launch.                  |
| `NOTCH_DEBUG_CONFIG=1` | Open the configurator on the first widget at launch.     |
| `NOTCH_SUPPORT_DIR=…`  | Point Application Support somewhere disposable.          |
| `NOTCH_RUNNER_PATH=…`  | Use a locally built custom-metric runner.                |

`NOTCH_DEBUG_EXPAND` pins rather than merely expanding, and that matters: the
exit watch installed on expand finds the pointer elsewhere and collapses within
half a second, so an unpinned debug expand is useless for a screenshot.

```bash
NOTCH_DEBUG_EXPAND=1 NOTCH_DEBUG_DEMO=1 \
  apps/mac/build/DerivedData/Build/Products/Debug/NotchMetrics.app/Contents/MacOS/NotchMetrics
```

Run the binary directly rather than via `open` when you need environment
variables — `open` does not pass the caller's environment through.

## Why `install-local.sh` kills the running copy first

The app is `LSUIElement`, so it has **no Cmd-Q** and `osascript … quit` does
nothing. Without the kill, the old copy keeps running over the new one — which
looks exactly like a fix that did not work.

It also copies with `/usr/bin/ditto`, never `cp -R`. `ditto` preserves extended
attributes and the nested structure the signature covers; a `cp`-copied bundle
fails validation and macOS reports that as **"the application is damaged"**,
which sends people hunting for the wrong problem.

## State and logs

```
~/Library/Application Support/NotchMetrics/
  settings.json  layout.json  session.json
  metrics/<id>/              # custom metrics (see the custom-metric skill)
  logs/app-*.log  logs/plugins/<id>.log  logs/update.log
~/Library/Caches/com.notchmetrics.app/
  metrics/  Updates/
```

To reset: quit, `rm -rf ~/Library/Application\ Support/NotchMetrics`, relaunch.

## "It logged me out after I rebuilt"

Expected, not a bug. Keychain items are bound to the signing identity, so
moving between an ad-hoc Debug build and a Developer ID Release build
invalidates the ACL. `KeychainSecretStore` surfaces `errSecInteractionNotAllowed`
and `errSecAuthFailed` as `SecretStoreError.identityChanged` so the UI can ask
for a sign-in rather than crash on an opaque `OSStatus`.

The same applies to any macOS permission grant: TCC keys them to the bundle
signature, and an ad-hoc signature changes on every build.

## Before you commit

```bash
pnpm mac:gen && pnpm mac:test
node scripts/sync-mac-version.mjs --check
pnpm format
```

And a changeset naming `@notch/mac` — CI fails without one. See `versioning`.
