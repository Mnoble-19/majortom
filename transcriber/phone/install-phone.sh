#!/usr/bin/env bash
# Build and install onto the iPhone. Also the weekly re-sign: a free Apple
# account's provisioning profile lasts seven days, after which the app stops
# launching until this is run again. Nothing about the app causes that — it is
# a property of the account.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null \
        | awk '/\(UDID\)/ && !/simulated/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f-]{25,}$/) { print $i; exit } }')
fi

if [[ -z "$DEVICE" ]]; then
    echo "No iPhone found. Plug it in, unlock it, and turn any VPN off —"
    echo "a VPN blocks the connection the tunnel needs, and the failure it"
    echo "produces says nothing about VPNs."
    exit 1
fi

echo "› device $DEVICE"
echo "› building"
xcodebuild -project MajorTomPhone.xcodeproj -scheme MajorTomPhone \
    -destination "id=$DEVICE" -configuration Debug \
    -allowProvisioningUpdates build >/dev/null

APP=$(find ~/Library/Developer/Xcode/DerivedData/MajorTomPhone-*/Build/Products/Debug-iphoneos \
    -maxdepth 1 -name "MajorTom.app" 2>/dev/null | head -1)
[[ -n "$APP" ]] || { echo "built, but no .app came out — check the build output"; exit 1; }

echo "› installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

EXPIRY=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
    | plutil -extract ExpirationDate raw - 2>/dev/null || true)
echo "› done${EXPIRY:+ — signing expires $EXPIRY}"
