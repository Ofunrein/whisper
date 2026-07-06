#!/bin/bash
# Build Whisper.app from the SPM executable.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Whisperer.app
rm -rf build/Whisper.app "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Whisper "$APP/Contents/MacOS/Whisper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

# Ad-hoc signing deliberately avoids touching any signing certificate in
# macOS Keychain. Provider keys are no longer stored in Keychain, so stable
# cert identity is not needed, and cert signing can itself cause password
# prompts on rebuild.
codesign --force --deep --sign - "$APP"
# Also install into /Applications so Raycast/Spotlight index it as a real app,
# not a transient repo build artifact that loses to Superwhisper.app.
INSTALL_APP=/Applications/Whisperer.app
rm -rf "$INSTALL_APP"
ditto "$APP" "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP" >/dev/null 2>&1 || true
mdimport "$INSTALL_APP" >/dev/null 2>&1 || true
echo "Built $APP"
echo "Installed $INSTALL_APP"
