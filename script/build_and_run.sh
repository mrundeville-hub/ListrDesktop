#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ListrDesktop"
BUNDLE_ID="dev.listr.desktop"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="1.0.0"
BUILD_NUMBER="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

if [[ ! -f "$ICON_SRC" ]]; then
    swift "$ROOT_DIR/script/generate_app_icon.swift" \
        "$ROOT_DIR/Resources/AppIcon.iconset" "$ICON_SRC"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -f "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc (-s -) runs on this Mac only. Set LISTR_CODESIGN_IDENTITY to a
# "Developer ID Application: ..." identity for a build other Macs will open;
# hardened runtime + secure timestamp are what notarization requires.
if [[ -n "${LISTR_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
        -s "$LISTR_CODESIGN_IDENTITY" \
        --entitlements "$ROOT_DIR/ListrDesktop.entitlements" "$APP_BUNDLE"
else
    codesign --force -s - --entitlements "$ROOT_DIR/ListrDesktop.entitlements" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not start" >&2
    exit 1
    ;;
  --dmg|dmg)
    # ponytail: bare hdiutil, no fancy DMG layout
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"
    ;;
  --notarize|notarize)
    # Requires a Developer ID build and a stored keychain profile:
    #   xcrun notarytool store-credentials listr-notary \
    #     --apple-id <id> --team-id <team> --password <app-specific-password>
    : "${LISTR_CODESIGN_IDENTITY:?set LISTR_CODESIGN_IDENTITY to a Developer ID identity and re-run the build first}"
    NOTARY_PROFILE="${LISTR_NOTARY_PROFILE:-listr-notary}"
    DMG="$DIST_DIR/$APP_NAME.dmg"
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "Notarized and stapled: $DMG"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--dmg|--notarize]" >&2
    exit 2
    ;;
esac
