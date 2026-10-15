#!/usr/bin/env bash
# The local equivalent of .github/workflows/release-mirror.yml.
#
# Earns its place because the recovery path for a failed mirror must not be
# "edit a workflow and push a commit". Same environment variable names as the
# workflow, so the credentials are interchangeable.
set -euo pipefail

TAG="${1:-}"
[ -n "$TAG" ] || { echo "usage: mirror-release.sh mac-v0.2.0"; exit 2; }
case "$TAG" in mac-v*) ;; *) echo "::error::$TAG is not a Mac release tag."; exit 1 ;; esac

: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}"
: "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
# R2 rejects the AWS CLI's default integrity headers with an error that reads
# as a credentials problem.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
export AWS_DEFAULT_REGION=auto

BUCKET="${BUCKET:-notch}"
PREFIX="${PREFIX:-desktop}"
PUBLIC_URL="${PUBLIC_URL:-https://assets.notchmetrics.com}"
# The release notes a user can actually open. The repository is private, so a
# GitHub release URL is a sign-in wall for everybody but the author.
SITE_URL="${SITE_URL:-https://notchmetrics.com}"
ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
VERSION="${TAG#mac-v}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh release download "$TAG" --pattern '*.dmg' --dir "$WORK"
FILE="$(basename "$(ls "$WORK"/*.dmg)")"

current=$(curl -fsSL "$PUBLIC_URL/$PREFIX/latest.json" 2>/dev/null \
  | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1) || current=""
if [ -n "$current" ]; then
  newest=$(printf '%s\n%s\n' "$current" "$VERSION" | sort -V | tail -n 1)
  if [ "$newest" != "$VERSION" ] && [ "$current" != "$VERSION" ]; then
    echo "::error::latest.json already points at $current, which is newer than $VERSION."
    exit 1
  fi
fi

aws s3 cp "$WORK/$FILE" "s3://$BUCKET/$PREFIX/$VERSION/$FILE" \
  --endpoint-url "$ENDPOINT" \
  --content-type application/x-apple-diskimage \
  --cache-control "public, max-age=31536000, immutable" \
  --only-show-errors

# Out of the disk image, not out of Config/Version.xcconfig.
#
# The updater compares latest.json's `build` with the running app's
# CFBundleVersion, so those two integers have to come from the same place.
# The xcconfig in this checkout is not that place: CI regenerates it from a
# run number, and a hand-run mirror of an older tag reads whatever the working
# tree happens to hold. Reading it out of the bundle being published cannot
# drift.
MOUNT="$(mktemp -d)"
hdiutil attach "$WORK/$FILE" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$MOUNT"/*.app/Contents/Info.plist)"
BUNDLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$MOUNT"/*.app/Contents/Info.plist)"
hdiutil detach "$MOUNT" -force >/dev/null

case "$BUILD" in ''|*[!0-9]*) echo "::error::CFBundleVersion is '$BUILD', not an integer."; exit 1 ;; esac
[ "$BUILD" -gt 0 ] || { echo "::error::CFBundleVersion is 0."; exit 1; }
[ "$BUNDLED_VERSION" = "$VERSION" ] || {
  echo "::error::$FILE contains $BUNDLED_VERSION, not the $VERSION its name claims."
  exit 1
}

jq -n \
  --arg version "$VERSION" --argjson build "$BUILD" --arg tag "$TAG" \
  --arg publishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg minimumSystemVersion "14.0" --arg filename "$FILE" \
  --arg url "$PUBLIC_URL/$PREFIX/$VERSION/$FILE" \
  --arg sha256 "$(shasum -a 256 "$WORK/$FILE" | cut -d' ' -f1)" \
  --arg notes "$SITE_URL/changelog#v$(echo "$VERSION" | tr . -)" \
  --argjson size "$(stat -f%z "$WORK/$FILE")" \
  '{ version: $version, build: $build, tag: $tag, publishedAt: $publishedAt,
     platform: "darwin-arm64", minimumSystemVersion: $minimumSystemVersion,
     filename: $filename, url: $url, size: $size, sha256: $sha256,
     notes: $notes, mandatory: false }' > "$WORK/latest.json"

cat "$WORK/latest.json"

aws s3 cp "$WORK/latest.json" "s3://$BUCKET/$PREFIX/latest.json" \
  --endpoint-url "$ENDPOINT" \
  --content-type application/json \
  --cache-control "public, max-age=60" \
  --only-show-errors

# Through the public domain, not the bucket: this is what catches a write that
# landed behind a custom domain which is not actually serving it.
curl -fsSL "$PUBLIC_URL/$PREFIX/latest.json" | grep -q "\"version\": \"$VERSION\""
echo "==> mirrored $TAG"
