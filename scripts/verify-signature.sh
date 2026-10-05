#!/usr/bin/env bash
# The checks a user's Mac will make, made here first.
#
# Shared by CI and by the `signing` skill deliberately: two lists of
# verification commands drift, and the one that drifts is always the one in the
# documentation.
set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: verify-signature.sh <path to .app or .dmg>"; exit 2; }

echo "==> codesign -dv"
codesign -dv --verbose=4 "$TARGET" 2>&1 | sed 's/^/    /'

echo "==> the signature is valid and complete"
codesign --verify --deep --strict --verbose=2 "$TARGET"

echo "==> the notarisation ticket is stapled to the artefact itself"
# This is the check that distinguishes "notarised" from "notarised and will
# still open on a Mac with no network".
xcrun stapler validate "$TARGET"

case "$TARGET" in
  *.app)
    echo "==> Gatekeeper accepts it as an installed app"
    # Expect: "source=Notarized Developer ID". Anything else — including
    # "source=Unnotarized Developer ID" — means users will see a warning.
    spctl -a -vvv -t install "$TARGET"
    ;;
  *.dmg)
    echo "==> Gatekeeper accepts the disk image"
    spctl -a -t open --context context:primary-signature -v "$TARGET"
    ;;
esac

echo "==> all checks passed"
