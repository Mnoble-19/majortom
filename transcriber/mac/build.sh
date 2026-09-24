#!/usr/bin/env bash
# Builds MajorTom Calls.app. Same approach as desktop/build.sh: SwiftPM produces
# a bare binary, so the bundle is assembled by hand and there is no .xcodeproj
# to keep in sync.
#
# The bundle is not optional. Capturing the mic and tapping another app's audio
# both need TCC permission, and TCC identifies an app by its bundle id and code
# signature — a loose binary gets asked every launch, or refused outright.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

ICON=build/AppIcon.icns
[[ "$ICON" -nt ../../desktop/make-icon.swift ]] || swift ../../desktop/make-icon.swift "$ICON" --calls

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MajorTomCalls"

APP="build/MajorTom Calls.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MajorTomCalls"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signing is enough for TCC to recognise the app across launches, so the
# permission prompts appear once rather than every time.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
