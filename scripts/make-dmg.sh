#!/bin/bash
# Build Whisper.app (via make-app.sh) then package it as a drag-to-Applications DMG.
# No Apple Developer signing/notarization involved -- the DMG carries whatever
# stable local designated requirement make-app.sh embedded.
# First launch on another Mac will still need right-click > Open (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION 2>/dev/null || echo "0.0.0")"
"$(dirname "$0")/make-app.sh"

APP=build/Whisper.app
STAGING=build/dmg-staging
DMG="build/Whisper-${VERSION}.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Whisper.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Whisper ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "Built $DMG"
