#!/usr/bin/env bash
# Builds MajorTom.app. SwiftPM produces a bare binary, so the bundle is
# assembled by hand — there is no .xcodeproj to keep in sync.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
REPO="$(cd .. && pwd)"

[[ Resources/AppIcon.icns -nt make-icon.swift ]] || swift make-icon.swift Resources/AppIcon.icns

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MajorTom"

APP="build/MajorTom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MajorTom"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

# Baked in so the app still finds data/ and the unpacked extension from /Applications.
/usr/libexec/PlistBuddy -c "Add :MTRepoRoot string $REPO" "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
