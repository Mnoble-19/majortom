#!/usr/bin/env bash
# Registers the native messaging host with every Chromium browser on this Mac,
# so whichever one you are watching in hands saved words to the same database.
#
#   ./install-host.sh <extension-id>... [--app /path/to/MajorTom.app]
#
# Extension ids are shown on the card at chrome://extensions. An unpacked
# extension's id is derived from its folder, so loading the same folder in
# Chrome and Brave gives the same id and one argument covers both; pass several
# only if you loaded it from different folders.
set -euo pipefail
cd "$(dirname "$0")"

APP="$(pwd)/build/MajorTom.app"
HOST_NAME="com.majortom.host"
EXT_IDS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        *) EXT_IDS+=("$1"); shift ;;
    esac
done

if [[ ${#EXT_IDS[@]} -eq 0 ]]; then
    echo "usage: ./install-host.sh <extension-id>... [--app /path/to/MajorTom.app]" >&2
    exit 1
fi

ORIGINS=""
for id in "${EXT_IDS[@]}"; do
    [[ -n "$ORIGINS" ]] && ORIGINS+=", "
    ORIGINS+="\"chrome-extension://$id/\""
done

BIN="$APP/Contents/MacOS/MajorTom"
if [[ ! -x "$BIN" ]]; then
    echo "no binary at $BIN — run ./build.sh first" >&2
    exit 1
fi

TARGETS=(
    "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    "$HOME/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts"
    "$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser-Beta/NativeMessagingHosts"
    "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
    "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    "$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts"
    "$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
)

found=0
for dir in "${TARGETS[@]}"; do
    parent="$(dirname "$dir")"
    [[ -d "$parent" ]] || continue
    mkdir -p "$dir"
    cat > "$dir/$HOST_NAME.json" <<JSON
{
  "name": "$HOST_NAME",
  "description": "MajorTom desktop sync",
  "path": "$BIN",
  "type": "stdio",
  "allowed_origins": [$ORIGINS]
}
JSON
    echo "registered in $(basename "$parent")"
    found=$((found + 1))
done

if [[ $found -eq 0 ]]; then
    echo "no Chromium browsers found under ~/Library/Application Support" >&2
    exit 1
fi

echo "done — all $found write to $(cd .. && pwd)/data/majortom.sqlite"
echo "reload the extension, then save a word"
