---
name: signing
description: Diagnose macOS code signing and notarisation failures. Use when someone pastes errSecInternalComponent, "0 valid identities found", "code object is not signed at all", "The signature does not include a secure timestamp", "The binary is not signed with a valid Developer ID certificate", a notarytool rejection, a stapler error, or when an app opens on the machine that built it and is "damaged" or blocked everywhere else. Separate from the release skill on purpose — the trigger here is an error message, not an intent to ship.
---

# Signing and notarisation

## First, read the actual rejection

```bash
xcrun notarytool log <submission-id> \
  --key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER"
```

This is the only output that names the offending path. The summary line
(`status: Invalid`) never does, and people routinely skip this step and spend
an afternoon guessing.

## Symptom → cause

| What you see                                                     | What it is                                                                                                                                                                  |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `errSecInternalComponent`                                        | `security set-key-partition-list` was not run after importing the `.p12`, or the keychain is locked. On a runner, `codesign` is blocking on a GUI prompt nobody can answer. |
| `0 valid identities found`, cert clearly imported                | The keychain is not in the **search list**. `security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user \| tr -d '"')`                                |
| `code object is not signed at all`                               | A nested binary was missed. Sign inside-out: helpers and frameworks first, the bundle last. `--deep` is a diagnostic, not a fix.                                            |
| `The signature does not include a secure timestamp`              | `--timestamp` missing. It is on `OTHER_CODE_SIGN_FLAGS` in `build-mac.sh` so nested code gets it too.                                                                       |
| `The binary is not signed with a valid Developer ID certificate` | An **Apple Distribution** or **Apple Development** certificate. Both sign happily; only Developer ID passes Gatekeeper outside the App Store.                               |
| `Team is not yet configured for notarization`                    | The Apple Developer Program agreement has not been accepted for this team.                                                                                                  |
| Opens here, "damaged" elsewhere                                  | Either it was never notarised, or it was copied with `cp -R`. Use `/usr/bin/ditto`.                                                                                         |
| Works until the Mac goes offline                                 | The app has no ticket of its own — only the disk image was stapled. See below.                                                                                              |

## Staple the app _and_ the image

Stapling a `.dmg` attaches the ticket to the **image**, not to the app inside
it. Somebody who mounts it is fine; somebody who drags the app to
`/Applications`, unzips the `.zip`, or is handed the bundle by an MDM has an
app that passes only while that Mac can reach Apple. It fails on a plane.

`sign-and-notarize.sh` therefore submits twice. It costs three to eight minutes
of macOS runner time per release. Pay it.

## Local setup

```bash
security find-identity -v -p codesigning        # want: Developer ID Application

# Store the notarisation credentials once, then forget them:
xcrun notarytool store-credentials notch-notary \
  --key ~/keys/AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer xxxxxxxx-…
export APPLE_KEYCHAIN_PROFILE=notch-notary
```

`sign-and-notarize.sh` accepts either the profile or the `APPLE_API_KEY` trio.
Note that `APPLE_API_KEY` is a **path to the `.p8`**, not the key's contents —
the CI secret is called `APPLE_API_KEY_BASE64` precisely because it is decoded
to a file first.

## Do not reach for `disable-library-validation`

It appears in every search result and it will usually make the error go away.
It also disables a hardened-runtime protection for the life of the product.

The real cause is almost always an **unsigned or badly-signed embedded binary**.
Find it:

```bash
codesign --verify --deep --strict --verbose=2 NotchMetrics.app
find NotchMetrics.app -type f -perm +111 -exec codesign -dv {} \; 2>&1 | grep -B1 "not signed"
```

This app's entitlements file is two keys long. If it is growing, something is
wrong upstream of the entitlement.

## Verify

```bash
scripts/verify-signature.sh <path to .app or .dmg>
```

One script, shared by CI and this document, so the two cannot drift. It runs
`codesign -dv`, `codesign --verify --deep --strict`, `stapler validate` and
`spctl`. The `spctl` line is the one that matters: expect
`source=Notarized Developer ID`.
