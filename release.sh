#!/bin/bash
# Cuts a release: universal build, zipped, published to GitHub Releases.
#
#   ./release.sh 0.2.0
#
# `ditto` is used rather than `zip` because it preserves the bundle's symlinks and
# extended attributes; a plain zip can produce an .app that will not launch.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: ./release.sh <version>    e.g. ./release.sh 0.2.0" >&2
    exit 1
fi

TAG="v$VERSION"
ZIP="Semaphoz-$VERSION.zip"

VERSION="$VERSION" ./build.sh --universal

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent Semaphoz.app "$ZIP"

gh release create "$TAG" "$ZIP" \
    --title "Semaphoz $VERSION" \
    --notes "See the [install instructions](https://github.com/bbonfim/semaphoz#install) — Semaphoz is not signed with an Apple Developer ID, so macOS needs one extra confirmation on first launch.

Universal binary: Apple Silicon and Intel. Requires macOS 13 or later."

rm -f "$ZIP"
echo "Released $TAG"
