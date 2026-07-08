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
# No nested code (frameworks/plugins/embedded binaries) exists in this bundle
# -- just one Mach-O plus plain data resources -- so --deep is unnecessary.
# --timestamp=none is the real fix for codesign hanging indefinitely against
# this bundle in a non-interactive shell (root-caused 2026-07-07, second
# pass): codesign defaults to contacting Apple's timestamp authority server
# over the network, which can hang or stall silently on a flaky/proxied
# connection. A local dev-signing cert has no need for a trusted timestamp
# anyway. (An earlier theory blamed Keychain ACLs / --deep; those may have
# been red herrings from network flakiness happening to coincide with the
# same retries -- --timestamp=none is what actually reproduces reliably.)
SIGN_ID="Whisper Dev Signing"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
sign_with_dev_cert() {
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" 20 codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
  else
    codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
  fi
}
if security find-identity -v -p codesigning | grep -q "$SIGN_ID" && sign_with_dev_cert; then
  :
else
  echo "" >&2
  echo "############################################################" >&2
  echo "# WARNING: dev cert signing missing or timed out.           #" >&2
  echo "# Falling back to AD-HOC SIGNING for this build.            #" >&2
  echo "#                                                            #" >&2
  echo "# Ad-hoc signing changes the app's identity on EVERY build,  #" >&2
  echo "# which silently invalidates macOS Accessibility trust even  #" >&2
  echo "# though the toggle in System Settings still shows 'on'.     #" >&2
  echo "# Run scripts/install-dev-cert.sh, then rebuild, before      #" >&2
  echo "# relying on Accessibility features (auto-paste, hotkeys).   #" >&2
  echo "############################################################" >&2
  echo "" >&2
  codesign --force --sign - --timestamp=none "$APP"
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
