#!/bin/bash
# Builds HerdrMenuBar and assembles it into a .app bundle.
#
# The bundle is not optional: UNUserNotificationCenter refuses to work for a
# bare executable, and SMAppService needs a bundle identifier to register a
# login item. Ad-hoc signing is enough for local use.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
APP="build/Herdr Menu Bar.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/HerdrMenuBar"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HerdrMenuBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Built: $APP"
