#!/usr/bin/env bash
# Archives and exports the app. Signing is a separate step — see
# sign-and-notarize.sh — because Xcode's own notarisation during export hides
# the submission id and gives a one-line failure instead of the log that names
# the offending binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC="$ROOT/apps/mac"
BUILD="$MAC/build"
CONFIGURATION="Release"
SIGN=1

while [ $# -gt 0 ]; do
  case "$1" in
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --no-sign) SIGN=0; shift ;;
    *) echo "unknown argument: $1"; exit 2 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "::error::xcodegen is not installed. brew install xcodegen"; exit 1; }

node "$ROOT/scripts/sync-mac-version.mjs"
node "$ROOT/scripts/sync-mac-config.mjs"

# The metric runner, before xcodegen, because project.yml copies it in as a
# resource and declares it `optional` — a missing bundle is a warning there,
# not an error. Built here so that cannot quietly ship an app whose custom
# metrics have nothing to run: `PluginRunner` would throw `runnerMissing` and
# every local tile would read "Runner missing".
echo "==> building the metric runner"
# Through `pnpm runner`, which is turbo, so `dependsOn: ["^build"]` builds
# `@notchmetrics/core` first. Filtering straight to the package skips that,
# and `@notch/schemas` imports core by package name with its `exports`
# pointing at `dist/` — so esbuild cannot resolve it on a clean checkout.
# That is what failed the 0.4.0 release twice.
(cd "$ROOT" && pnpm runner >/dev/null)
[ -f "$ROOT/packages/metric-runtime/dist/runner.mjs" ] || {
  echo "::error::the runner did not build; custom metrics would not run in this app"
  exit 1
}

(cd "$MAC" && xcodegen generate)

mkdir -p "$BUILD"

SIGNING_ARGS=()
if [ "$SIGN" = "1" ]; then
  SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=Developer ID Application"
    DEVELOPMENT_TEAM=2WH7TUH8N5
    # Here rather than in a later codesign pass, so nested frameworks are
    # timestamped too. Notarisation rejects an un-timestamped signature, and
    # the rejection names a framework rather than this decision.
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
else
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
fi

beautify() { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }

echo "==> archiving ($CONFIGURATION)"
set -o pipefail
xcodebuild archive \
  -project "$MAC/NotchMetrics.xcodeproj" \
  -scheme NotchMetrics \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD/NotchMetrics.xcarchive" \
  -derivedDataPath "$BUILD/DerivedData" \
  -clonedSourcePackagesDirPath "$BUILD/SourcePackages" \
  "${SIGNING_ARGS[@]}" \
  | tee "$BUILD/archive.log" | beautify

if [ "$SIGN" = "0" ]; then
  echo "==> unsigned build at $BUILD/DerivedData/Build/Products/$CONFIGURATION"
  exit 0
fi

echo "==> exporting"
rm -rf "$BUILD/export"
xcodebuild -exportArchive \
  -archivePath "$BUILD/NotchMetrics.xcarchive" \
  -exportOptionsPlist "$MAC/ExportOptions.plist" \
  -exportPath "$BUILD/export" \
  | tee -a "$BUILD/archive.log" | beautify

APP="$BUILD/export/NotchMetrics.app"
[ -d "$APP" ] || { echo "::error::no app at $APP"; exit 1; }

# Checked on the artefact rather than on the intent. An environment variable
# cannot see a URL compiled into a Swift string literal.
#
# NOTCH_ALLOW_LOCAL_URLS=1 is for installing a signed build against a local
# Worker, which is the only backend that exists before Cloudflare is
# provisioned. It is the same override check-release-env.mjs takes, so setting
# it in CI would let a localhost build out as a release — set it on the
# command line for a local install, never in a workflow.
if [ "${NOTCH_ALLOW_LOCAL_URLS:-0}" = "1" ]; then
  echo "==> skipping the development-URL check (NOTCH_ALLOW_LOCAL_URLS=1)"
else
  echo "==> checking for development URLs"
  # Info.plist, not the Mach-O. The URLs arrive as `NMAPIBaseURL` and friends
  # from Config.xcconfig, which lands in the plist — never as a literal in
  # the binary. This check used to grep `strings` on the executable, where
  # the value it was looking for cannot appear, so it passed on every build
  # and a notch pointed at localhost:8787 was installed to /Applications
  # looking exactly like one that worked.
  if grep -aE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)' "$APP/Contents/Info.plist" \
    || strings -a "$APP/Contents/MacOS/NotchMetrics" \
      | grep -nE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)'; then
    echo "::error::a localhost URL is baked into this build."
    echo "::error::Config.xcconfig comes from .env — set NEXT_PUBLIC_API_URL and friends,"
    echo "::error::or for a deliberate local install: NOTCH_ALLOW_LOCAL_URLS=1 pnpm mac:ship"
    exit 1
  fi
fi

echo "==> $APP"
