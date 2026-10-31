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

# Ad-hoc signature so macOS can ask for Automation (AppleScript) permission.
codesign --force --deep --sign - "$APP"

echo "Built $(pwd)/$APP"
echo "Run it with:  open \"$(pwd)/$APP\""
