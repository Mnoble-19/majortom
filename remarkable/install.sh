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
LABEL="com.majortom.remarkable-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"

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

say "Installing the sync agent…"
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

cat > "$PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$HERE/sync.py</string>
    </array>
    <!-- The tablet is usually absent, and sync.py exits in under a second when
         it is. Polling is simpler than trying to get launchd to notice a USB
         ethernet interface appearing. -->
    <key>StartInterval</key>
    <integer>120</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/$LABEL.log</string>
</dict>
</plist>
PLIST_END

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

say "Done."
cat <<EOF

  Plugin      $PLUGIN_DIR
  Agent       $PLIST
  Log         $LOG_DIR/$LABEL.log

Restart KOReader on the tablet to load the plugin.

While reading: select a word or sentence, tap "Save to MajorTom", and it
translates, shows it, and saves if you confirm. Saves land in the Books tab
within two minutes of the tablet being plugged in.

To import by hand:        ./sync.py
To see without importing: ./sync.py --dry-run
To stop the agent:        launchctl bootout gui/$UID/$LABEL
EOF
