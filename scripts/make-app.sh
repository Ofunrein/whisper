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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(cat VERSION)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

# Keep one designated requirement across local builds without Keychain
# prompts. Plain ad-hoc signing defaults to a changing cdhash requirement,
# which invalidates Accessibility after every rebuild. Embedding the stable
# bundle identifier requirement keeps TCC grants attached to this app.
REQUIREMENTS="$(mktemp)"
trap 'rm -f "$REQUIREMENTS"' EXIT
printf 'designated => identifier "com.whisper.dictation";\n' > "$REQUIREMENTS"
codesign --force --sign - --timestamp=none -r "$REQUIREMENTS" "$APP"
# Also install into /Applications so Raycast/Spotlight index it as a real app,
# not a transient repo build artifact that loses to Superwhisper.app.
INSTALL_APP=/Applications/Whisper.app
rm -rf "$INSTALL_APP" /Applications/Whisperer.app
ditto "$APP" "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP" >/dev/null 2>&1 || true
mdimport "$INSTALL_APP" >/dev/null 2>&1 || true
echo "Built $APP"
echo "Installed $INSTALL_APP"
