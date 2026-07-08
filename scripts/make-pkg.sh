#!/bin/bash
# Build Whisper.app (via make-app.sh) then package it as a .pkg installer.
# No Apple Developer signing/notarization -- --sign is intentionally omitted,
# so this produces an unsigned "distribution" pkg. Installing it on another
# Mac requires right-click > Open (Gatekeeper), same as the DMG path.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION 2>/dev/null || echo "0.0.0")"
"$(dirname "$0")/make-app.sh"

APP=build/Whisper.app
PKGROOT=build/pkg-root
COMPONENT_PKG=build/Whisper-component.pkg
PKG="build/Whisper-${VERSION}.pkg"

rm -rf "$PKGROOT" "$COMPONENT_PKG" "$PKG"
mkdir -p "$PKGROOT/Applications"
ditto "$APP" "$PKGROOT/Applications/Whisper.app"

pkgbuild \
  --root "$PKGROOT" \
  --identifier com.whisper.dictation \
  --version "$VERSION" \
  --install-location / \
  "$COMPONENT_PKG"

productbuild \
  --package "$COMPONENT_PKG" \
  "$PKG"

rm -rf "$PKGROOT" "$COMPONENT_PKG"
echo "Built $PKG"
