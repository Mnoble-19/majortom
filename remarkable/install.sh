#!/usr/bin/env bash
#
# Installs both halves: the capture plugin onto the tablet, and the agent that
# imports from it on the Mac.
#
# The tablet must be plugged in over USB. Everything it writes goes under
# /home/root, which survives reMarkable firmware updates.

set -euo pipefail

TABLET="root@10.11.99.1"
KOREADER="/home/root/xovi/exthome/appload/koreader"
PLUGIN_DIR="$KOREADER/plugins/majortom.koplugin"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

say "Checking the tablet…"
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" true 2>/dev/null; then
    echo "Cannot reach the tablet at $TABLET." >&2
    echo "Plug it in over USB. If this is a new Mac, run: ssh-copy-id $TABLET" >&2
    exit 1
fi

if ! ssh -o BatchMode=yes "$TABLET" "[ -d $KOREADER ]" 2>/dev/null; then
    echo "KOReader is not installed at $KOREADER." >&2
    echo "Install it with ReManager (remanager.io) first." >&2
    exit 1
fi

say "Installing the plugin…"
ssh -o BatchMode=yes "$TABLET" "mkdir -p $PLUGIN_DIR"
scp -q "$HERE/majortom.koplugin/main.lua" "$HERE/majortom.koplugin/_meta.lua" "$TABLET:$PLUGIN_DIR/"

# A syntax error here would only surface as KOReader silently skipping the
# plugin, so fail loudly now instead.
if ! ssh -o BatchMode=yes "$TABLET" \
    "cd $KOREADER && ./luajit -e 'assert(loadfile(\"plugins/majortom.koplugin/main.lua\"))'" 2>/dev/null; then
    echo "The plugin does not parse on the device." >&2
    exit 1
fi

say "Done."
cat <<EOF

  Plugin      $PLUGIN_DIR

Restart KOReader on the tablet to load the plugin.

While reading: select a word or sentence, tap "Save to MajorTom", and it
translates, shows it, and saves if you confirm.

Nothing imports on its own. Plug the tablet in and press Sync in the desktop
app's Books tab, or run it here:

  ./sync.py               import now
  ./sync.py --dry-run     show what is on the tablet, write nothing
EOF
