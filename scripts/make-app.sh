#!/bin/bash
# Build Whisper.app from the SPM executable.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Whisper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Whisper "$APP/Contents/MacOS/Whisper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

# Sign with a persistent local cert (not ad-hoc): ad-hoc signing hashes the
# binary itself, so every rebuild gets a new identity and macOS treats it as
# a brand-new untrusted app — re-prompting for Keychain access to the stored
# API keys on every launch. A stable cert keeps the same identity across
# rebuilds. Falls back to ad-hoc if the cert isn't installed (see
# scripts/install-dev-cert.sh).
SIGN_ID="Whisper Dev Signing"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --deep --sign "$SIGN_ID" "$APP"
else
    echo "Warning: '$SIGN_ID' identity not found, falling back to ad-hoc signing (Keychain will re-prompt each rebuild). Run scripts/install-dev-cert.sh once to fix."
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
