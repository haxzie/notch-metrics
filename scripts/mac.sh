#!/usr/bin/env bash
# Everyday Swift commands. `gen` is the one that matters: a new .swift file
# does not exist as far as Xcode is concerned until xcodegen has run, and the
# compiler reports that as "cannot find X in scope" — which names the wrong
# problem entirely.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC="$ROOT/apps/mac"

gen() {
  command -v xcodegen >/dev/null || { echo "::error::xcodegen is not installed. brew install xcodegen"; exit 1; }
  node "$ROOT/scripts/sync-mac-version.mjs"
  node "$ROOT/scripts/sync-mac-config.mjs"
  (cd "$MAC" && xcodegen generate)
}

case "${1:-gen}" in
  gen) gen ;;
  run)
    gen
    "$ROOT/scripts/build-mac.sh" --configuration Debug --no-sign
    open "$MAC/build/DerivedData/Build/Products/Debug/NotchMetrics.app"
    ;;
  test)
    gen
    # `swift test` rather than an Xcode test bundle: the Kit is where the logic
    # lives, and this runs without a scheme and therefore without generating
    # the project in CI.
    (cd "$MAC/Kit" && swift test)
    ;;
  open) gen && open "$MAC/NotchMetrics.xcodeproj" ;;
  *) echo "usage: mac.sh [gen|run|test|open]"; exit 2 ;;
esac
