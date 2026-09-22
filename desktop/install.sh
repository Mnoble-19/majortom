#!/usr/bin/env bash
# One-shot: build the extension, build the app, put it in /Applications and
# open it. The app registers itself with every browser on launch, so this is
# the only command — after it, MajorTom is a Dock icon like anything else.
set -euo pipefail
cd "$(dirname "$0")"

echo "› building extension"
(cd .. && npm run build >/dev/null)

echo "› building app"
./build.sh release >/dev/null

DEST="/Applications/MajorTom.app"
echo "› installing to $DEST"
rm -rf "$DEST"
cp -R build/MajorTom.app "$DEST"

echo "› launching"
open "$DEST"

cat <<'EOF'

Done. MajorTom is in /Applications — drag it to your Dock.

Remaining one-time step, in each browser you use:
  1. chrome://extensions → Developer mode
  2. Load unpacked → pick this repo's dist/extension folder

The app has already registered itself as that extension's sync host, so
saving a word will just work.
EOF
