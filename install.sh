#!/bin/bash
# Builds Semaphoz and installs it to ~/Applications, then enables launch at login.
#
# A stable install location matters here: the login item registration follows the app
# bundle's path, and build.sh deletes and recreates the bundle in the project directory
# on every build. Installing puts the launched copy somewhere that does not move.
#
# ~/Applications rather than /Applications so no admin password is needed.
set -euo pipefail

cd "$(dirname "$0")"

DEST="$HOME/Applications"
APP="$DEST/Semaphoz.app"

./build.sh

mkdir -p "$DEST"
pkill Semaphoz 2>/dev/null || true
sleep 1

rm -rf "$APP"
cp -R Semaphoz.app "$APP"

# Register from the installed copy, so the login item points at the stable path.
"$APP/Contents/MacOS/Semaphoz" --enable-login-item

open "$APP"
echo "Installed to $APP"
