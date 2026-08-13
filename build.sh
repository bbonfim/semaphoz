#!/bin/bash
# Builds Semaphoz.app without Xcode — Command Line Tools are enough.
#
#   ./build.sh              native arch only (fast, for development)
#   ./build.sh --universal  arm64 + x86_64 (for releases, runs on Intel Macs too)
#
# VERSION may be overridden by the environment; release.sh sets it from the tag.
set -euo pipefail

cd "$(dirname "$0")"

APP="Semaphoz.app"
VERSION="${VERSION:-0.1.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Semaphoz</string>
    <key>CFBundleDisplayName</key>     <string>Semaphoz</string>
    <key>CFBundleIdentifier</key>      <string>at.benu.semaphoz</string>
    <key>CFBundleExecutable</key>      <string>Semaphoz</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Menu bar accessory: no Dock icon. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

BIN="$APP/Contents/MacOS/Semaphoz"

if [ "${1:-}" = "--universal" ]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    for arch in arm64 x86_64; do
        swiftc -O -target "${arch}-apple-macos13.0" -o "$TMP/Semaphoz-$arch" Sources/*.swift
    done
    lipo -create -output "$BIN" "$TMP/Semaphoz-arm64" "$TMP/Semaphoz-x86_64"
else
    swiftc -O -target "$(uname -m)-apple-macos13.0" -o "$BIN" Sources/*.swift
fi

# Ad-hoc signature. This is NOT a Developer ID signature — see README on Gatekeeper.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP ($VERSION, $(lipo -archs "$BIN" 2>/dev/null || echo "$(uname -m)"))"
