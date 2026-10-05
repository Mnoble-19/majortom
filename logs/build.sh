#!/usr/bin/env bash
# Builds MajorTom Logs.app, the same way as the other apps: SwiftPM makes the
# binary and the bundle is assembled by hand.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
REPO="$(cd .. && pwd)"

ICON=build/AppIcon.icns
[[ "$ICON" -nt ../desktop/make-icon.swift ]] || swift ../desktop/make-icon.swift "$ICON" --logs

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MajorTomLogs"

APP="build/MajorTom Logs.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MajorTomLogs"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

# Baked in so the app finds data/logs from /Applications.
/usr/libexec/PlistBuddy -c "Add :MTRepoRoot string $REPO" "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
