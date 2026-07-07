#!/bin/bash
# Build Whisper.app from the SPM executable.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Whisper.app
rm -rf build/Whisperer.app "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Whisper "$APP/Contents/MacOS/Whisper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

# Stable local signing keeps macOS TCC Accessibility trust attached across
# rebuilds. Ad-hoc signing changes cdhash every build, so the Accessibility
# checkbox can look enabled while AXIsProcessTrusted() returns false.
# Bounded with a timeout: a Keychain private-key-access prompt can silently
# hang forever in a non-interactive/headless shell (no dialog ever appears
# to answer), which previously stalled builds indefinitely. Fall back to
# ad-hoc signing if the dev cert doesn't finish signing promptly.
SIGN_ID="Whisper Dev Signing"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
sign_with_dev_cert() {
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" 20 codesign --force --deep --sign "$SIGN_ID" "$APP"
  else
    codesign --force --deep --sign "$SIGN_ID" "$APP"
  fi
}
if security find-identity -v -p codesigning | grep -q "$SIGN_ID" && sign_with_dev_cert; then
  :
else
  echo "Dev cert signing missing or timed out; falling back to ad-hoc signing" >&2
  codesign --force --deep --sign - "$APP"
fi
# Also install into /Applications so Raycast/Spotlight index it as a real app,
# not a transient repo build artifact that loses to Superwhisper.app.
INSTALL_APP=/Applications/Whisper.app
rm -rf "$INSTALL_APP" /Applications/Whisperer.app
ditto "$APP" "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP" >/dev/null 2>&1 || true
mdimport "$INSTALL_APP" >/dev/null 2>&1 || true
echo "Built $APP"
echo "Installed $INSTALL_APP"
