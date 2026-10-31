#!/bin/bash
# Builds build/PetAgents.app from the Swift package and the sprites in ../preview.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/PetAgents.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PetAgents "$APP/Contents/MacOS/PetAgents"
cp Info.plist "$APP/Contents/Info.plist"
cp ../preview/manifest.js "$APP/Contents/Resources/manifest.js"
cp -R ../preview/strips "$APP/Contents/Resources/strips"

# App icon, drawn from the sprites by the app itself.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
.build/release/PetAgents --export-icon build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon_1024.png

# Sign with the stable local certificate when it exists (see make-signing-cert.sh), so macOS keeps
# Accessibility / Automation permissions across rebuilds. Otherwise fall back to an ad-hoc signature,
# which macOS treats as a brand-new app after every build.
IDENTITY="Pet Agents Local Signing"
if security find-certificate -c "$IDENTITY" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\"."
else
  codesign --force --deep --sign - "$APP"
  echo "Ad-hoc signed. Run app/make-signing-cert.sh once so permissions survive rebuilds."
fi

echo "Built $(pwd)/$APP"
echo "Run it with:  open \"$(pwd)/$APP\""
