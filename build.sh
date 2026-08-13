#!/bin/bash
# Builds Semaphoz.app without Xcode — Command Line Tools are enough.
set -euo pipefail

cd "$(dirname "$0")"

APP="Semaphoz.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Semaphoz</string>
    <key>CFBundleDisplayName</key>     <string>Semaphoz</string>
    <key>CFBundleIdentifier</key>      <string>at.benu.semaphoz</string>
    <key>CFBundleExecutable</key>      <string>Semaphoz</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Menu bar accessory: no Dock icon. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

swiftc -O \
    -target "${ARCH}-apple-macos13.0" \
    -o "$APP/Contents/MacOS/Semaphoz" \
    Sources/*.swift

# Ad-hoc signature keeps macOS from re-prompting on every rebuild.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
