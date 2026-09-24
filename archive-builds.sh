#!/usr/bin/env bash
# Builds every app from the current checkout and zips the results into
# builds/<date>-<label>/, so older versions stay around to compare against.
#
#   ./archive-builds.sh redesign
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
OUT="$ROOT/builds/$(date +%F)-${1:?usage: ./archive-builds.sh <label>}"
mkdir -p "$OUT"

(cd desktop && ./build.sh release >/dev/null)
(cd desktop/build && ditto -c -k --keepParent MajorTom.app "$OUT/MajorTom-mac.zip")

(cd transcriber/mac && ./build.sh release >/dev/null)
(cd transcriber/mac/build && ditto -c -k --keepParent "MajorTom Calls.app" "$OUT/MajorTom-Calls-mac.zip")

(cd extension && npm run build >/dev/null)
(cd extension/dist && zip -qry "$OUT/MajorTom-extension.zip" unpacked)

PHONE="$(mktemp -d)"
xcodebuild -project transcriber/phone/MajorTomPhone.xcodeproj -scheme MajorTomPhone \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$PHONE" -allowProvisioningUpdates -quiet build
mkdir -p "$PHONE/Payload"
cp -R "$PHONE/Build/Products/Release-iphoneos/MajorTom.app" "$PHONE/Payload/"
(cd "$PHONE" && zip -qry "$OUT/MajorTom-iPhone.ipa" Payload)
rm -rf "$PHONE"

git log -1 --format='Built from %h (%s) on %ad' --date=short > "$OUT/SOURCE.txt"
echo "archived to $OUT"
