#!/usr/bin/env bash
# Signs, notarises and staples an .app or a .dmg.
#
# The ordering in release-mac.yml is the whole value of this script, and it is
# worth stating once: notarise and staple the **app**, then build the disk
# image from the stapled app, then sign, notarise and staple the **image** too.
#
# Two submissions, not one. Stapling a disk image attaches the ticket to the
# image, not to the app inside it. Somebody who mounts the image is fine either
# way — but somebody who drags the app to /Applications, or is handed the
# bundle by an MDM, then has an app with no ticket of its own: it passes only
# while that Mac can reach Apple's notary service, and fails on a plane or
# behind a locked-down proxy. The extra three to eight minutes of macOS runner
# time is the price of that not being a support ticket.
set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: sign-and-notarize.sh <path to .app or .dmg>"; exit 2; }
[ -e "$TARGET" ] || { echo "::error::$TARGET does not exist"; exit 1; }

IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

notary_args() {
  if [ -n "${APPLE_KEYCHAIN_PROFILE:-}" ]; then
    echo "--keychain-profile ${APPLE_KEYCHAIN_PROFILE}"
  elif [ -n "${APPLE_API_KEY:-}" ]; then
    echo "--key ${APPLE_API_KEY} --key-id ${APPLE_API_KEY_ID} --issuer ${APPLE_API_ISSUER}"
  else
    echo ""
  fi
}

NOTARY="$(notary_args)"
if [ -z "$NOTARY" ]; then
  echo "::error::no notarisation credentials."
  echo "Either set APPLE_API_KEY (a path to the .p8), APPLE_API_KEY_ID and APPLE_API_ISSUER,"
  echo "or store a profile once with:"
  echo "  xcrun notarytool store-credentials notch-notary --key ~/keys/AuthKey_XXXX.p8 --key-id … --issuer …"
  echo "and set APPLE_KEYCHAIN_PROFILE=notch-notary."
  exit 1
fi

# Idempotent: Apple rate-limits submissions and each round trip is minutes, so
# a re-run after a later step failed must not re-submit what already passed.
if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then
  echo "==> $TARGET is already notarised and stapled; nothing to do"
  exit 0
fi

case "$TARGET" in
  *.app)
    echo "==> verifying the signature xcodebuild produced"
    codesign --verify --deep --strict --verbose=2 "$TARGET"
    # Checked before spending a round trip on Apple. A build without the
    # hardened runtime is rejected, and the rejection arrives ten minutes later.
    codesign -dv --verbose=4 "$TARGET" 2>&1 | grep -q 'flags=.*runtime' || {
      echo "::error::the hardened runtime is not enabled on $TARGET"
      exit 1
    }

    ZIP="${TARGET%.app}.zip"
    echo "==> zipping for submission"
    # `ditto`, not `zip -r`. notarytool will not accept a bare .app, and a
    # zip -r archive of a bundle can arrive with a signature Apple rejects.
    /usr/bin/ditto -c -k --keepParent --sequesterRsrc "$TARGET" "$ZIP"

    echo "==> notarising the app"
    # shellcheck disable=SC2086
    xcrun notarytool submit "$ZIP" $NOTARY --wait --timeout 30m

    echo "==> stapling the app"
    xcrun stapler staple "$TARGET"
    ;;

  *.dmg)
    echo "==> signing the disk image"
    codesign --sign "$IDENTITY" --timestamp --force "$TARGET"

    echo "==> notarising the disk image"
    # shellcheck disable=SC2086
    xcrun notarytool submit "$TARGET" $NOTARY --wait --timeout 30m

    echo "==> stapling the disk image"
    xcrun stapler staple "$TARGET"
    ;;

  *)
    echo "::error::expected a .app or a .dmg, got $TARGET"
    exit 2
    ;;
esac

"$ROOT/scripts/verify-signature.sh" "$TARGET"
