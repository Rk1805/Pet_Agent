#!/bin/bash
# Builds build/ShinobiPets.app from the Swift package and the sprites in ../preview.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/ShinobiPets.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ShinobiPets "$APP/Contents/MacOS/ShinobiPets"
cp Info.plist "$APP/Contents/Info.plist"
cp ../preview/manifest.js "$APP/Contents/Resources/manifest.js"
cp -R ../preview/strips "$APP/Contents/Resources/strips"

# Ad-hoc signature so macOS can ask for Automation (AppleScript) permission.
codesign --force --deep --sign - "$APP"

echo "Built $(pwd)/$APP"
echo "Run it with:  open \"$(pwd)/$APP\""
