#!/usr/bin/env bash
# Builds the installer disk image.
#
# Uses `create-dmg` from Homebrew — https://github.com/create-dmg/create-dmg,
# the shell script. NOT `npm install create-dmg`, which is a different tool
# with the same name: sindresorhus's zero-config Node CLI. It is good, it has
# none of the layout flags below, and it rejects them. This is a build-time
# dependency installed with `brew install create-dmg`; it must never appear in
# package.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC="$ROOT/apps/mac"
APP="${1:-$MAC/build/export/NotchMetrics.app}"
VERSION="$(node -p "require('$MAC/package.json').version")"
DMG="${2:-$MAC/build/NotchMetrics-$VERSION-arm64.dmg}"
VOLUME="Notch Metrics"

[ -d "$APP" ] || { echo "::error::no app at $APP"; exit 1; }
mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"

detach_volume() {
  hdiutil detach "/Volumes/$VOLUME" -force >/dev/null 2>&1 || true
}

plain_image() {
  echo "==> falling back to an unstyled disk image"
  local staging
  staging="$(mktemp -d)"
  /usr/bin/ditto "$APP" "$staging/$(basename "$APP")"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname "$VOLUME" -srcfolder "$staging" -ov -format UDBZ "$DMG"
  rm -rf "$staging"
}

if ! command -v create-dmg >/dev/null; then
  echo "create-dmg is not installed (brew install create-dmg)"
  plain_image
  exit 0
fi

BACKGROUND="$MAC/Resources/dmg-background.tiff"
BACKGROUND_ARGS=()
[ -f "$BACKGROUND" ] && BACKGROUND_ARGS=(--background "$BACKGROUND")

# Where the icons go, written by the same script that drew the arrow pointing
# between them. Sourced rather than repeated here: the two were duplicate
# literals held together by a comment, and a background redrawn for a new
# layout would have left the arrow aimed at empty window.
#
# Defaults for a checkout without the generated file — an unstyled window with
# the icons in the right half is a better failure than no disk image.
DMG_WINDOW_W=660 DMG_WINDOW_H=420 DMG_ICON_SIZE=128
DMG_ICON_Y=166 DMG_APP_X=165 DMG_DROP_X=495
# shellcheck source=/dev/null
[ -f "$MAC/Resources/dmg-layout.sh" ] && . "$MAC/Resources/dmg-layout.sh"

# create-dmg is the flakiest step in the whole pipeline and it is better to
# plan for that than to discover it. It drives Finder over AppleScript to place
# the icons, which on a hosted runner intermittently fails to unmount — and it
# exits 2 on a non-fatal SetFile or detach warning even when the image it
# produced is perfect. So: retry, treat "exit non-zero but the file is there"
# as success, and keep an escape hatch, because being blocked on installer
# cosmetics is never a good reason to be blocked.
for attempt in 1 2 3; do
  echo "==> create-dmg (attempt $attempt)"
  if create-dmg \
    --volname "$VOLUME" \
    "${BACKGROUND_ARGS[@]}" \
    --window-pos 200 120 \
    --window-size "$DMG_WINDOW_W" "$DMG_WINDOW_H" \
    --icon-size "$DMG_ICON_SIZE" \
    --icon "NotchMetrics.app" "$DMG_APP_X" "$DMG_ICON_Y" \
    --app-drop-link "$DMG_DROP_X" "$DMG_ICON_Y" \
    --hide-extension "NotchMetrics.app" \
    --no-internet-enable \
    --format UDBZ \
    "$DMG" "$APP"; then
    break
  fi
  [ -f "$DMG" ] && { echo "==> create-dmg exited non-zero but produced a valid image"; break; }
  detach_volume
  rm -f "$DMG"
  sleep 5
done

if [ ! -f "$DMG" ]; then
  if [ "${NOTCH_DMG_PLAIN:-0}" = "1" ]; then
    plain_image
  else
    echo "::error::create-dmg failed three times."
    echo "Set NOTCH_DMG_PLAIN=1 to ship an unstyled but perfectly valid image."
    exit 1
  fi
fi

echo "==> $DMG"
