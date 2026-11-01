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

# Sign with the stable local certificate (see make-signing-cert.sh), so macOS keeps Accessibility /
# Automation permissions across rebuilds. Without it, fall back to an ad-hoc signature, which macOS
# treats as a brand-new app after every build.
IDENTITY="Pet Agents Local Signing"
KC="$HOME/Library/Keychains/pet-agents-signing.keychain-db"
if [ -f "$KC" ]; then
  security unlock-keychain -p "pet-agents-local" "$KC"
  HASH=$(security find-identity -p codesigning "$KC" | awk -v n="\"$IDENTITY\"" 'index($0, n) {print $2; exit}')
  if [ -z "$HASH" ]; then
    echo "error: \"$IDENTITY\" not found in $KC. Delete that keychain and run app/make-signing-cert.sh again." >&2
    exit 1
  fi
  codesign --force --deep --keychain "$KC" --sign "$HASH" "$APP"
  echo "Signed with \"$IDENTITY\"."
elif security find-certificate -c "$IDENTITY" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  # Older setup (certificate in the login keychain): works, but macOS may ask for your password.
  # Run app/make-signing-cert.sh to switch to the prompt-free keychain.
  echo "Signing with \"$IDENTITY\" from your login keychain (macOS may ask for your password)…"
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\"."
else
  codesign --force --deep --sign - "$APP"
  echo "Ad-hoc signed. Run app/make-signing-cert.sh once so permissions survive rebuilds."
fi

echo "Built $(pwd)/$APP"
echo "Run it with:  open \"$(pwd)/$APP\""
