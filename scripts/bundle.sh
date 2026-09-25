#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${BOTCH_VERSION#v}"
VERSION="${VERSION:-0.0.0}"
ARCHS="${BOTCH_ARCHS:-arm64}"
DIST="dist"
APP="$DIST/Botch.app"

arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done
swift build -c release --product Botch "${arch_flags[@]}"
BIN="$(swift build -c release --product Botch "${arch_flags[@]}" --show-bin-path)/Botch"

rm -rf "$APP" "$DIST/dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Botch"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$DIST/Botch.zip" "$DIST/Botch.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Botch.zip"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/Botch.app"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -quiet -volname Botch -srcfolder "$DIST/dmg" -ov -format UDZO "$DIST/Botch.dmg"
rm -rf "$DIST/dmg"
echo "Built $APP ($VERSION, $ARCHS)"
