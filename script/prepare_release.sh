#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Usage: prepare_release.sh VERSION BUILD [release-notes.md]}"
BUILD="${2:?A monotonically increasing build number is required}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid version/build" >&2; exit 2; }
IDENTITIES="$(security find-identity -v -p codesigning | sed -nE '/"Developer ID Application:/s/.* ([0-9A-F]{40}) .*/\1/p')"
SIGNING_IDENTITY="${SNAPLET_DISTRIBUTION_IDENTITY:-$IDENTITIES}"
if [[ -z "$SIGNING_IDENTITY" ]] || ! printf '%s\n' "$IDENTITIES" | grep -Fxq "$SIGNING_IDENTITY"; then
  echo "Release requires a valid Developer ID Application identity. Configure SNAPLET_DISTRIBUTION_IDENTITY; development certificates cannot be published." >&2
  exit 2
fi
: "${SNAPLET_NOTARY_PROFILE:?Configure a notarytool Keychain profile in SNAPLET_NOTARY_PROFILE}"
FEED_FILE="$(mktemp /private/tmp/snaplet-feed.XXXXXX)"
ARCHIVE_STAGE="$(mktemp -d /private/tmp/snaplet-archive.XXXXXX)"
trap 'rm -f "$FEED_FILE"; rm -rf "$ARCHIVE_STAGE"' EXIT
python3 "$ROOT_DIR/script/validate_release.py" "$VERSION" "$BUILD" > "$FEED_FILE"
SNAPLET_DISTRIBUTION=1 SNAPLET_SIGNING_IDENTITY="$SIGNING_IDENTITY" SNAPLET_VERSION="$VERSION" SNAPLET_BUILD="$BUILD" "$ROOT_DIR/script/build_and_run.sh" --package
OUTPUT_DIR="$ROOT_DIR/dist/releases/v$VERSION"
mkdir -p "$OUTPUT_DIR"
cp "$FEED_FILE" "$OUTPUT_DIR/appcast.xml"
ARCHIVE="$OUTPUT_DIR/Snaplet-$VERSION.zip"
ditto --noextattr --norsrc "$ROOT_DIR/dist/Snaplet.app" "$ARCHIVE_STAGE/Snaplet.app"
xattr -cr "$ARCHIVE_STAGE/Snaplet.app"
codesign --verify --deep --strict "$ARCHIVE_STAGE/Snaplet.app"
ditto -c -k --noextattr --norsrc --keepParent "$ARCHIVE_STAGE/Snaplet.app" "$ARCHIVE_STAGE/notarize.zip"
xcrun notarytool submit "$ARCHIVE_STAGE/notarize.zip" --keychain-profile "$SNAPLET_NOTARY_PROFILE" --wait
xcrun stapler staple "$ARCHIVE_STAGE/Snaplet.app"
xcrun stapler validate "$ARCHIVE_STAGE/Snaplet.app"
spctl --assess --type execute --verbose=4 "$ARCHIVE_STAGE/Snaplet.app"
ditto -c -k --noextattr --norsrc --keepParent "$ARCHIVE_STAGE/Snaplet.app" "$ARCHIVE"
mkdir "$ARCHIVE_STAGE/verify"
ditto -x -k "$ARCHIVE" "$ARCHIVE_STAGE/verify"
codesign --verify --deep --strict "$ARCHIVE_STAGE/verify/Snaplet.app"
spctl --assess --type execute --verbose=4 "$ARCHIVE_STAGE/verify/Snaplet.app"
if [[ -n "${3:-}" ]]; then cp "$3" "$OUTPUT_DIR/Snaplet-$VERSION.md"; fi
"$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --account com.local.lightcapture.updates --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/pskishere/Snaplet/releases/download/v$VERSION/" "$OUTPUT_DIR"
echo "Prepared signed archive and appcast: $OUTPUT_DIR (not published)"
