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

# Ad-hoc signing deliberately avoids touching any signing certificate in
# macOS Keychain. Provider keys are no longer stored in Keychain, so stable
# cert identity is not needed, and cert signing can itself cause password
# prompts on rebuild.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
