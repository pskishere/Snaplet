#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Usage: prepare_release.sh VERSION BUILD [release-notes.md]}"
BUILD="${2:?A monotonically increasing build number is required}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid version/build" >&2; exit 2; }
FEED_FILE="$(mktemp /private/tmp/snaplet-feed.XXXXXX)"
ARCHIVE_STAGE="$(mktemp -d /private/tmp/snaplet-archive.XXXXXX)"
trap 'rm -f "$FEED_FILE"; rm -rf "$ARCHIVE_STAGE"' EXIT
python3 "$ROOT_DIR/script/validate_release.py" "$VERSION" "$BUILD" > "$FEED_FILE"
SNAPLET_VERSION="$VERSION" SNAPLET_BUILD="$BUILD" "$ROOT_DIR/script/build_and_run.sh" --package
OUTPUT_DIR="$ROOT_DIR/dist/releases/v$VERSION"
mkdir -p "$OUTPUT_DIR"
cp "$FEED_FILE" "$OUTPUT_DIR/appcast.xml"
ARCHIVE="$OUTPUT_DIR/Snaplet-$VERSION.zip"
ditto --noextattr --norsrc "$ROOT_DIR/dist/Snaplet.app" "$ARCHIVE_STAGE/Snaplet.app"
xattr -cr "$ARCHIVE_STAGE/Snaplet.app"
codesign --verify --deep --strict "$ARCHIVE_STAGE/Snaplet.app"
ditto -c -k --noextattr --norsrc --keepParent "$ARCHIVE_STAGE/Snaplet.app" "$ARCHIVE"
mkdir "$ARCHIVE_STAGE/verify"
ditto -x -k "$ARCHIVE" "$ARCHIVE_STAGE/verify"
codesign --verify --deep --strict "$ARCHIVE_STAGE/verify/Snaplet.app"
if [[ -n "${3:-}" ]]; then cp "$3" "$OUTPUT_DIR/Snaplet-$VERSION.md"; fi
"$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --account com.local.lightcapture.updates --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/pskishere/Snaplet/releases/download/v$VERSION/" "$OUTPUT_DIR"
echo "Prepared signed archive and appcast: $OUTPUT_DIR (not published)"
