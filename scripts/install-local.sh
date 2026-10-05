#!/usr/bin/env bash
# Replaces the installed copy with the one just built.
#
# Shell rather than Node on purpose: the Swift development loop should not need
# pnpm to be installed or node_modules to be present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/apps/mac/build/export/NotchMetrics.app}"
DEST="/Applications/NotchMetrics.app"

[ -d "$APP" ] || { echo "::error::no app at $APP"; exit 1; }

# The app is LSUIElement, so it has no Cmd-Q and `osascript ... quit` does
# nothing. Without this the old copy keeps running over the new one, which
# looks exactly like a fix that did not work.
if pgrep -f "NotchMetrics.app" >/dev/null; then
  echo "==> quitting the running copy"
  pkill -f "NotchMetrics.app" || true
  for _ in $(seq 1 50); do
    pgrep -f "NotchMetrics.app" >/dev/null || break
    sleep 0.1
  done
  if pgrep -f "NotchMetrics.app" >/dev/null; then
    echo "==> it did not stop; forcing"
    pkill -9 -f "NotchMetrics.app" || true
    sleep 0.5
  fi
fi

echo "==> installing to $DEST"
rm -rf "$DEST"
# `ditto`, never `cp -R`. It preserves extended attributes, symlinks and the
# nested structure the code signature covers; a cp-copied bundle fails
# validation and macOS reports that as "the application is damaged", which
# sends people looking for the wrong problem entirely.
/usr/bin/ditto "$APP" "$DEST"

echo "==> launching"
open "$DEST"
