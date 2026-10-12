#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="Snaplet"
APP_VERSION="${SNAPLET_VERSION:-1.0.0}"
APP_BUILD="${SNAPLET_BUILD:-1}"
UPDATE_KEY="$(cat "$ROOT_DIR/Assets/UpdatePublicKey.txt")"
SIGN_OPTIONS=(--timestamp=none)
if [[ "${SNAPLET_DISTRIBUTION:-0}" == 1 ]]; then
  SIGN_OPTIONS=(--timestamp --options runtime)
fi
SIGNING_CONFIG="$ROOT_DIR/.codex/signing-identity"
SIGNING_IDENTITY="${SNAPLET_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$SIGNING_CONFIG" ]]; then
  SIGNING_IDENTITY="$(cat "$SIGNING_CONFIG")"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning | sed -nE '/"Apple Development:/s/.* ([0-9A-F]{40}) .*/\1/p')"
  COUNT="$(printf '%s\n' "$IDENTITIES" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$COUNT" != 1 ]]; then
    echo "需要固定的开发签名证书。请设置 SNAPLET_SIGNING_IDENTITY 为证书指纹（security find-identity -v -p codesigning）。" >&2
    exit 1
  fi
  SIGNING_IDENTITY="$IDENTITIES"
fi
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "开发构建不能使用临时签名，否则重编译可能丢失截图授权。" >&2
  exit 1
fi
STAGING_DIR="$(mktemp -d /private/tmp/lightcapture.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/Snaplet.app"
if [[ "$MODE" != "--package" ]]; then
  pkill -x LightCapture >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
swift build -c release
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto --noextattr --norsrc "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_BUNDLE/Contents/Resources" "$STAGING_DIR/AppIcon.iconset"
cp -R "$ROOT_DIR/Assets/Localizations/"*.lproj "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/Assets/SnapletLogo.png" "$APP_BUNDLE/Contents/Resources/SnapletLogo.png"
swift "$ROOT_DIR/script/render_app_icon.swift" "$ROOT_DIR/Assets/SnapletLogo.png" "$STAGING_DIR/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$STAGING_DIR/AppIcon.png" --out "$STAGING_DIR/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$STAGING_DIR/AppIcon.png" --out "$STAGING_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snaplet</string>
<key>CFBundleIdentifier</key><string>com.local.lightcapture</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>en</string><string>ja</string><string>ko</string><string>fr</string><string>de</string><string>es</string><string>pt</string><string>it</string><string>ru</string></array>
<key>CFBundleName</key><string>Snaplet</string>
<key>CFBundleDisplayName</key><string>Snaplet</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/pskishere/Snaplet/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>$UPDATE_KEY</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAllowsAutomaticUpdates</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUSendProfileInfo</key><false/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP_BUNDLE"
SPARKLE_CODE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
for NESTED_CODE in "$SPARKLE_CODE/XPCServices/Downloader.xpc" "$SPARKLE_CODE/XPCServices/Installer.xpc" "$SPARKLE_CODE/Autoupdate" "$SPARKLE_CODE/Updater.app" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"; do
  codesign --force "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$NESTED_CODE"
done
codesign --force "${SIGN_OPTIONS[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
mkdir -p "$ROOT_DIR/.codex"
if [[ "${SNAPLET_DISTRIBUTION:-0}" != 1 ]]; then
  printf '%s\n' "$SIGNING_IDENTITY" > "$SIGNING_CONFIG"
fi
mkdir -p "$ROOT_DIR/dist"
ditto --noextattr --norsrc "$APP_BUNDLE" "$ROOT_DIR/dist/Snaplet.app"
APP_BUNDLE="$ROOT_DIR/dist/Snaplet.app"
if [[ "$MODE" == "--package" ]]; then
  echo "$APP_BUNDLE"
  exit 0
fi
mkdir -p "$HOME/Applications"
ditto --noextattr --norsrc "$STAGING_DIR/Snaplet.app" "$HOME/Applications/Snaplet.app"
APP_BUNDLE="$HOME/Applications/Snaplet.app"
codesign --verify --strict "$APP_BUNDLE"
# Refresh Launch Services after replacing a development bundle at the same path.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"
case "$MODE" in
run) /usr/bin/open -n "$APP_BUNDLE" ;;
--verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" ;;
--debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
--logs|--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Snaplet"' ;;
*) echo "Usage: $0 [run|--verify|--package|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
