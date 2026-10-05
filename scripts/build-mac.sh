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
echo "==> checking for development URLs in the binary"
if strings -a "$APP/Contents/MacOS/NotchMetrics" \
  | grep -nE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)' ; then
  echo "::error::a localhost URL is compiled into the binary"
  exit 1
fi

echo "==> $APP"
