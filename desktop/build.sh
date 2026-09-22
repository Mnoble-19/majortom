#!/usr/bin/env bash
# Builds MajorTom.app. SwiftPM produces a bare binary, so the bundle is
# assembled by hand — there is no .xcodeproj to keep in sync.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MajorTom"

APP="build/MajorTom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MajorTom"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
